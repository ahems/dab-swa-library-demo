---
page_type: sample
languages:
- azurecli
- azstatic-cli
- nodejs
- javascript
- data-api-builder
products:
- azure
- static-web-apps
- azure-sql-database
urlFragment: sample
name: Jamstack Library App with Azure Static Web Apps, Data API builder, and Azure SQL Database
description: This sample uses the database connections feature of Azure Static Web Apps to provide CRUD access to database contents with REST, built-in authorizations, and support for database relationships with GraphQL.
---
<!-- YAML front-matter schema: https://review.learn.microsoft.com/en-us/help/contribute/samples/process/onboarding?branch=main#supported-metadata-fields-for-readmemd -->

# Library Demo

A sample app of Static Web Apps with Database connections for a React app and Azure SQL database

## Features

This project uses the database connections feature of Static Web Apps to provide the following functionality:

* CRUD access to database contents with REST or GraphQL
* Built-in authorization with Static Web Apps authentication
* Support for database relationships with GraphQL

## Getting Started

### CodeSpaces

The easiest way to get started is to use GitHub CodeSpaces as all the tools are installed for you. Steps:

1. Click this button: [![Open in GitHub Codespaces](https://img.shields.io/static/v1?style=for-the-badge&label=GitHub+Codespaces&message=Open&color=brightgreen&logo=github)](https://github.com/codespaces/new?hide_repo_select=true&repo=1023713469&machine=standardLinux32gb&devcontainer_path=.devcontainer%2Fdevcontainer.json&location=WestUs2). This will launch the repo is VS Code in a Browser.
2. Next, you should launch the CodeSpace in *Visual Studio Code Dev Containers* because the Login from the command line using some corporate credentials may not work from a CodeSpace in a Browser. To do this, click the name of the Codespace in the bottom-left of the screen and select "Open in VS Code Desktop"
3. Once the project files show up in your desktop deployment of Visual Studio Code (this may take several minutes), use the terminal window to follow the steps below to configure Authentication and deploy the infrastructure.

### Deploying

The steps below will provision Azure resources and deploy the application code to an Azure Static Web App.

1. Login to the Azure Developer CLI (azd):

    ```shell
    azd auth login
    ```

    If this command fails, make sure you have launched in Visual Studio Code Dev Containers and are not still using a CodeSpace in the web browser (see Step 2 above)

2. Change to the root directory:

    ```shell
    cd library-demo/
    ```

3. Create a new azd environment:

    ```shell
    azd env new <yourname>-libraryDemo
    ```

    Enter a name that will be used for the resource group. It will automatically have "rg-" prepended and we recommend using your name to make it easy for others to see whose environment it is.

    This will create a new folder in the `.azure` folder, and set it as the active environment for any calls to `azd` going forward.
  
4. You are now ready to deploy the infrastructure and the app. Run this command, which will take 10 minutes or so to run:

    ```shell
    azd up
    ```

    This will provision Azure resources and deploy this sample to those resources. After the application has been successfully deployed you will see a URL printed to the console similar to the screenshot below at the end, where it says "- Endpoint:".

## Using the app

* You are now ready to use the application. Click the URL shown in Step 3 above to launch the application in your browser.

## Clean up

To clean up all the resources created by this sample:

1. Run `azd down`
2. When asked if you are sure you want to continue, enter `y`
3. When asked if you want to permanently delete the resources, enter `y`

The resource group and all the resources will be deleted.

### To get started locally

1. Clone this repository
2. Navigate to `library` directory & open with VSCode
3. Set the `DATABASE_CONNECTION_STRING` environment variable to your connection string in your terminal/cmd/powershell. Alternatively, paste your database connection string directly into `swa-db-connections/staticwebapp.database.config.json` (*not recommended*) (ensure that you remove this secret from your source code before pushing to GitHub/remote repository)
4. Run `swa start http://localhost:3000 --run "cd library-demo && npm i && npm start" swa-db-connections`
    * `cd library-demo && npm i && npm start` will install needed npm packages and run your React app
    * `--data-api-location swa-db-connections` indicates to the SWA CLI that your database connections configurations are in the `swa-db-connections` folder
Alternatively, you can start all these projects manually an make use of SWA CLI's other args

You can now use your Static Web App Library Demo Application. It supports authorization, such that anyone logged in with SWA CLI's authentication emulation with the `admin` role will have `CRUD` access, while anonymous users are limited to `read` access. See the configurations detailed in `staticwebapp.database.config.json`

## Screenshots

### Home page:
![alt text](./.readme/mainpage.png)

### Non-logged in users receive 403's when they try to Create as configured in `swa-db-connections/staticwebapp.database.config.json`
![alt text](./.readme/anonuserscreate.png)

### Non-logged in users receive 403's when they try to Delete as configured in `swa-db-connections/staticwebapp.database.config.json`
![alt text](./.readme/anonusersdelete.png)

### Log in page with `admin` role
![alt text](./.readme/authpage.png)

### Non-logged in users receive succesful 201's when they try to Create as configured in `swa-db-connections/staticwebapp.database.config.json`![alt text](./.readme/adminuserscreate.png)
