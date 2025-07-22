@description('The location used for all deployed resources')
param location string = resourceGroup().location

@description('Tags that will be applied to all resources')
param tags object = {}


var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = uniqueString(subscription().id, resourceGroup().id, location)
param sqlAdminUsername string = uniqueString(newGuid())
@secure()
param sqlAdminPassword string = newGuid()

// Monitor application with Azure Monitor
module monitoring 'br/public:avm/ptn/azd/monitoring:0.1.0' = {
  name: 'monitoring'
  params: {
    logAnalyticsName: '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    applicationInsightsName: '${abbrs.insightsComponents}${resourceToken}'
    applicationInsightsDashboardName: '${abbrs.portalDashboards}${resourceToken}'
    location: location
    tags: tags
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
      # Install SqlServer module with force and skip publisher check to avoid compatibility issues
      Write-Output "Installing SqlServer module..."
      Install-Module -Name SqlServer -Force -AllowClobber -SkipPublisherCheck -AcceptLicense -Scope CurrentUser
      
      # Import the module explicitly
      Write-Output "Importing SqlServer module..."
      Import-Module SqlServer -Force
      
      # Verify the module is loaded
      if (Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue) {
          Write-Output "SqlServer module loaded successfully"
      } else {
          Write-Error "SqlServer module failed to load Invoke-Sqlcmd cmdlet"
          throw "SqlServer module installation failed"
      }
      
      # Build connection string
      $connectionString = "Server=tcp:$($env:SQL_SERVER),1433;Initial Catalog=$($env:SQL_DATABASE);User ID=$($env:SQL_USERNAME);Password=$($env:SQL_PASSWORD);Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
      
      Write-Output "Testing connection..."
      try {
          Invoke-Sqlcmd -ConnectionString $connectionString -Query "SELECT 1 as TestConnection" -ErrorAction Stop
          Write-Output "Database connection successful!"
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
          Invoke-Sqlcmd -ConnectionString $connectionString -Query $createTablesQuery -ErrorAction Stop
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
          Invoke-Sqlcmd -ConnectionString $connectionString -Query $insertAuthorsQuery -ErrorAction Stop
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
          Invoke-Sqlcmd -ConnectionString $connectionString -Query $insertBooksQuery -ErrorAction Stop
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

// Static Web App using Azure Verified Module
module staticWebApp 'br/public:avm/res/web/static-site:0.1.0' = {
  name: 'staticWebApp'
  params: {
    name: '${abbrs.webStaticSites}libraryDemo-${resourceToken}'
    location: location
    tags: union(tags, {
      'azd-service-name': 'library-demo'
    })
    sku: 'Standard'
    buildProperties: {
      skipGithubActionWorkflowGeneration: true
    }
    provider: 'None'
    appSettings: {
      DATABASE_CONNECTION_STRING: 'Server=tcp:${database.outputs.fullyQualifiedDomainName},1433;Initial Catalog=${abbrs.sqlServersDatabases}Library-${resourceToken};Persist Security Info=False;User ID=${sqlAdminUsername};Password=${sqlAdminPassword};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=60;'
    }
  }
}
