/* ============================================================================
   Guardant Health — Snowflake Enablement Session
   03_git_integration.sql — connect this GitHub repo to Snowflake

   Creates the three objects Snowflake needs to read a private GitHub repo:
     1. a SECRET holding your GitHub credential
     2. an API INTEGRATION allowing outbound calls to your GitHub org
     3. a GIT REPOSITORY object that Snowflake can fetch and browse

   ------------------------------------------------------------------------
   BEFORE YOU RUN: replace <YOUR_GITHUB_PAT> below.

   Do NOT commit a real token to this file. Either edit it locally and leave
   the edit uncommitted, or run the CREATE SECRET statement separately, e.g.

     snow sql -c <connection> --role ACCOUNTADMIN -q "
       CREATE OR REPLACE SECRET DEMO.GUARDANT_DEMO.GUARDANT_GITHUB_SECRET
         TYPE = PASSWORD
         USERNAME = 'sfc-gh-pmatson'
         PASSWORD = '$(gh auth token)';"

   A fine-grained or classic PAT with read access to the repo is sufficient.
   ------------------------------------------------------------------------

   THIS REPO IS PUBLIC, so the credential is optional. If you would rather not
   create a secret at all, skip step 1 and drop both the
   ALLOWED_AUTHENTICATION_SECRETS clause and the GIT_CREDENTIALS clause below —
   Snowflake can fetch a public repo anonymously. The secret is kept here as the
   default because it is what you need for any private repo, which is the more
   common real-world case and the one worth showing the customer.
   ------------------------------------------------------------------------

   NOTE ON WORKSPACES: these objects give Snowflake read access to the repo and
   let you deploy notebooks from it (see 04_deploy_notebooks.sql). A git-backed
   *Workspace* — the thing you demo in the GitHub segment — can only be created
   in the Snowsight UI: Projects -> Workspaces -> From Git repository. There is
   no DDL or CLI equivalent.
   ============================================================================ */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE GUARDANT_DEMO_WH;
USE SCHEMA DEMO.GUARDANT_DEMO;

-- 1. Credential -------------------------------------------------------------
CREATE OR REPLACE SECRET GUARDANT_GITHUB_SECRET
  TYPE = PASSWORD
  USERNAME = 'sfc-gh-pmatson'
  PASSWORD = '<YOUR_GITHUB_PAT>'
  COMMENT = 'GitHub credential for the Guardant enablement repo';

-- 2. Outbound access to the GitHub org -------------------------------------
CREATE OR REPLACE API INTEGRATION GUARDANT_GITHUB_API_INTEGRATION
  API_PROVIDER = GIT_HTTPS_API
  API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-pmatson')
  ALLOWED_AUTHENTICATION_SECRETS = (GUARDANT_GITHUB_SECRET)
  ENABLED = TRUE
  COMMENT = 'Outbound GitHub access for the Guardant enablement repo';

-- 3. The repository ---------------------------------------------------------
CREATE OR REPLACE GIT REPOSITORY GUARDANT_ENABLEMENT_REPO
  API_INTEGRATION = GUARDANT_GITHUB_API_INTEGRATION
  GIT_CREDENTIALS = GUARDANT_GITHUB_SECRET
  ORIGIN = 'https://github.com/sfc-gh-pmatson/guardant-snowflake-enablement.git'
  COMMENT = 'Demo assets for the Guardant Health enablement session';

-- Pull the latest commit and confirm Snowflake can see the files.
ALTER GIT REPOSITORY GUARDANT_ENABLEMENT_REPO FETCH;

LS @GUARDANT_ENABLEMENT_REPO/branches/main/notebooks/;
