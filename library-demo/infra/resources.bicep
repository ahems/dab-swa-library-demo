@description('The location used for all deployed resources')
param location string = resourceGroup().location

@description('Tags that will be applied to all resources')
param tags object = {}


var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = uniqueString(subscription().id, resourceGroup().id, location)
param sqlAdminUsername string = uniqueString(newGuid())
@secure()
param sqlAdminPassword string = newGuid()

// Monitor application with Azure Monitor - Log Analytics with daily quota cap
module logAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.12.0' = {
  name: 'logAnalytics'
  params: {
    name: '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    location: location
    tags: tags
    dailyQuotaGb: 1  // Set daily data cap to 1GB (minimum amount)
    dataRetention: 0  // Minimum retention period for cost optimization
    skuName: 'PerGB2018'  // Pay-as-you-go pricing tier
  }
}

// Application Insights connected to the Log Analytics workspace
module applicationInsights 'br/public:avm/res/insights/component:0.4.1' = {
  name: 'applicationInsights'
  params: {
    name: '${abbrs.insightsComponents}${resourceToken}'
    location: location
    tags: tags
    workspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
    applicationType: 'web'
  }
}

module libraryDemoIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.2.1' = {
  name: 'libraryDemoidentity'
  params: {
    name: '${abbrs.managedIdentityUserAssignedIdentities}libraryDemo-${resourceToken}'
    location: location
  }
}

module database 'br/public:avm/res/sql/server:0.15.0' = {
  name: 'sqlServer'
  params: {
    name: '${abbrs.sqlServers}${resourceToken}'
    location: location
    tags: tags
    administratorLogin: sqlAdminUsername
    administratorLoginPassword: sqlAdminPassword
    publicNetworkAccess: 'Enabled'
    firewallRules: [
      {
        name: 'AllowAllWindowsAzureIps'
        startIpAddress: '0.0.0.0'
        endIpAddress: '0.0.0.0'
      }
      {
        name: 'AllowAllIps'
        startIpAddress: '0.0.0.0'
        endIpAddress: '255.255.255.255'
      }
    ]
    databases: [
      {
        name: '${abbrs.sqlServersDatabases}Library-${resourceToken}'
        sku: {
          name: 'GP_S_Gen5_1'
          tier: 'GeneralPurpose'
          family: 'Gen5'
          capacity: 1
        }
        zoneRedundant: false
        readScale: 'Disabled'
        requestedBackupStorageRedundancy: 'Local'
        collation: 'SQL_Latin1_General_CP1_CI_AS'
        licenseType: 'BasePrice'
        autoPauseDelay: 60
        minCapacity: '0.5'
        maxSizeBytes: 34359738368
      }
    ]
    roleAssignments: [
      {
        principalId: libraryDemoIdentity.outputs.principalId
        roleDefinitionIdOrName: '056cd41c-7e88-42e1-933e-88ba6a50c9c3' // SQL DB Contributor
        principalType: 'ServicePrincipal'
      }
      {
        principalId: staticWebApp.identity.principalId
        roleDefinitionIdOrName: '056cd41c-7e88-42e1-933e-88ba6a50c9c3' // SQL DB Contributor
        principalType: 'ServicePrincipal'
      }
    ]
  }
}

// Deployment script to initialize database with schema and data
module databaseInitScript 'br/public:avm/res/resources/deployment-script:0.5.1' = {
  name: 'databaseInitScript'
  params: {
    name: 'init-database-${abbrs.sqlServersDatabases}Library-${resourceToken}'
    location: location
    tags: tags
    kind: 'AzurePowerShell'
    azPowerShellVersion: '14.2'
    managedIdentities: {
      userAssignedResourceIds: [
        libraryDemoIdentity.outputs.resourceId
      ]
    }
    timeout: 'PT5M'
    cleanupPreference: 'OnSuccess'
    environmentVariables: [
      {
        name: 'SQL_SERVER'
        value: database.outputs.fullyQualifiedDomainName
      }
      {
        name: 'SQL_DATABASE'
        value: '${abbrs.sqlServersDatabases}Library-${resourceToken}'
      }
      {
        name: 'SQL_USERNAME'
        value: sqlAdminUsername
      }
      {
        name: 'SQL_PASSWORD'
        secureValue: sqlAdminPassword
      }
    ]
    scriptContent: '''
      # Use .NET SqlClient instead of PowerShell SqlServer module to avoid package corruption issues
      Write-Output "Loading System.Data.SqlClient..."
      Add-Type -AssemblyName "System.Data.SqlClient"
      
      # Build connection string
      $connectionString = "Server=tcp:$($env:SQL_SERVER),1433;Initial Catalog=$($env:SQL_DATABASE);User ID=$($env:SQL_USERNAME);Password=$($env:SQL_PASSWORD);Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
      
      # Function to execute SQL commands using .NET SqlClient
      function Invoke-SqlQuery {
          param(
              [string]$ConnectionString,
              [string]$Query
          )
          
          $connection = New-Object System.Data.SqlClient.SqlConnection
          $connection.ConnectionString = $ConnectionString
          
          try {
              Write-Output "Executing query..."
              $connection.Open()
              $command = $connection.CreateCommand()
              $command.CommandText = $Query
              $command.CommandTimeout = 300  # 5 minutes timeout
              $result = $command.ExecuteNonQuery()
              Write-Output "Query executed successfully. Rows affected: $result"
              return $result
          }
          catch {
              Write-Error "SQL execution failed: $($_.Exception.Message)"
              throw
          }
          finally {
              if ($connection.State -eq 'Open') {
                  $connection.Close()
              }
          }
      }
      
      Write-Output "Testing connection..."
      try {
          $testConnection = New-Object System.Data.SqlClient.SqlConnection
          $testConnection.ConnectionString = $connectionString
          $testConnection.Open()
          Write-Output "Database connection successful!"
          $testConnection.Close()
      }
      catch {
          Write-Error "Connection test failed: $($_.Exception.Message)"
          throw
      }
      
      Write-Output "Creating tables..."
      
      # Create tables
      $createTablesQuery = @"
CREATE TABLE authors(
    id int IDENTITY(1,1) PRIMARY KEY,
    name varchar(255),
    birthdate date,
    bio text,
    imageurl varchar(max)
);

CREATE TABLE books(
    id int IDENTITY(1,1) PRIMARY KEY,
    title varchar(255),
    authorId int NOT NULL,
    genre varchar(255),
    publicationdate date,
    imageurl varchar(max),
    CONSTRAINT FK_books_authors FOREIGN KEY (authorId) REFERENCES authors(id)
);
"@

      try {
          Invoke-SqlQuery -ConnectionString $connectionString -Query $createTablesQuery
          Write-Output "Tables created successfully!"
      }
      catch {
          Write-Error "Failed to create tables: $($_.Exception.Message)"
          throw
      }
      
      Write-Output "Inserting sample data..."
      
      # Insert authors data
      $insertAuthorsQuery = @"
SET IDENTITY_INSERT authors ON;
INSERT INTO authors (id, name, birthdate, bio, imageurl) VALUES 
(1, 'Lewis Carroll', '1832-01-27', 'Lewis Carroll was an English author, poet, and mathematician known for his word play, logic, and fantasy.', 'https://upload.wikimedia.org/wikipedia/commons/f/fb/LewisCarrollSelfPhoto.jpg'),
(2, 'Antoine de Saint-Exupéry', '1900-06-29', 'Antoine de Saint-Exupéry was a French writer, poet, aristocrat, journalist, and aviator.', 'https://upload.wikimedia.org/wikipedia/commons/7/7f/11exupery-inline1-500.jpg');
SET IDENTITY_INSERT authors OFF;
"@

      try {
          Invoke-SqlQuery -ConnectionString $connectionString -Query $insertAuthorsQuery
          Write-Output "Authors data inserted successfully!"
      }
      catch {
          Write-Error "Failed to insert authors: $($_.Exception.Message)"
          throw
      }
      
      # Insert books data
      $insertBooksQuery = @"
SET IDENTITY_INSERT books ON;
INSERT INTO books (id, title, authorId, genre, imageurl) VALUES 
(1, 'Alice''s Adventures in Wonderland', 1, 'Fantasy', 'https://upload.wikimedia.org/wikipedia/commons/thumb/a/a9/Alice%27s_Adventures_in_Wonderland_cover_%281865%29.jpg/220px-Alice%27s_Adventures_in_Wonderland_cover_%281865%29.jpg'),
(2, 'Le Petit Prince', 2, NULL, 'https://upload.wikimedia.org/wikipedia/en/thumb/0/05/Littleprince.JPG/220px-Littleprince.JPG'),
(11, 'Through the Looking-Glass', 1, 'Fantasy', 'https://upload.wikimedia.org/wikipedia/commons/6/6c/Through_the_looking_glass.jpg');
SET IDENTITY_INSERT books OFF;
"@

      try {
          Invoke-SqlQuery -ConnectionString $connectionString -Query $insertBooksQuery
          Write-Output "Books data inserted successfully!"
          Write-Output "Database initialization completed!"
      }
      catch {
          Write-Error "Failed to insert books: $($_.Exception.Message)"
          throw
      }
    '''
    retentionInterval: 'PT1H'
  }
}

// Static Web App with Database Connection support (using direct resource for full feature access)
resource staticWebApp 'Microsoft.Web/staticSites@2024-04-01' = {
  name: '${abbrs.webStaticSites}libraryDemo-${resourceToken}'
  location: location
  tags: {
    'azd-service-name': 'library-demo'
  }
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    provider: 'None'
    buildProperties: {
      skipGithubActionWorkflowGeneration: true
    }
    enterpriseGradeCdnStatus: 'Disabled'
    stagingEnvironmentPolicy: 'Enabled'
    allowConfigFileUpdates: true
    publicNetworkAccess: 'Enabled'
  }
}

// App Settings for Static Web App - includes environment variables
resource staticWebAppSettings 'Microsoft.Web/staticSites/config@2024-04-01' = {
  name: 'appsettings'
  parent: staticWebApp
  properties: {
    AZURE_SQL_CONNECTION_STRING: 'Server=tcp:${database.outputs.fullyQualifiedDomainName},1433;Initial Catalog=${abbrs.sqlServersDatabases}Library-${resourceToken};User ID=${sqlAdminUsername};Password=${sqlAdminPassword};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
  }
}

// Database Connection for Static Web App
resource staticWebAppDatabaseConnection 'Microsoft.Web/staticSites/databaseConnections@2024-11-01' = {
  name: 'default'
  parent: staticWebApp
  properties: {
    resourceId: database.outputs.resourceId
    connectionString: 'Server=tcp:${database.outputs.fullyQualifiedDomainName},1433;Initial Catalog=${abbrs.sqlServersDatabases}Library-${resourceToken};User ID=${sqlAdminUsername};Password=${sqlAdminPassword};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
    region: location
  }
}

// Outputs for GitHub Actions and deployment
@description('The name of the Static Web App resource')
output STATIC_WEB_APP_NAME string = staticWebApp.name

@description('The default URL of the Static Web App')
output STATIC_WEB_APP_URL string = 'https://${staticWebApp.properties.defaultHostname}'

@description('The resource ID of the Static Web App')
output STATIC_WEB_APP_RESOURCE_ID string = staticWebApp.id

@description('The name of the database connection')
output DATABASE_CONNECTION_NAME string = staticWebAppDatabaseConnection.name

@description('The resource group name containing the Static Web App')
output RESOURCE_GROUP_NAME string = resourceGroup().name

@description('Instructions for getting the deployment token')
output DEPLOYMENT_TOKEN_INSTRUCTIONS string = 'Run: az staticwebapp secrets list --name ${staticWebApp.name} --resource-group ${resourceGroup().name} --query "properties.apiKey" --output tsv'
