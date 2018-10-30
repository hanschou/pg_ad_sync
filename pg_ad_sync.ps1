# Parameters must be first
Param (
    [switch]$Help=$false,
    [switch]$DropAdRoles=$false,
    [switch]$NoCaseRoles=$false,
	[string]$PgHost="",
	[string]$PgPort="",
	[string]$PgDatabase="",
	[string]$PgUser="",
	[string]$PgPassword=""
)
$ErrorActionPreference = "Stop"

# By Hans Schou 2018-10-19

# PostgreSQL configuration
# File pg_hba.conf:
#   host all all 10.0.0.0/8 ldap ldapserver=example.org ldapprefix="" ldapsuffix="@example.org"

if ($Help) {
	Write-Host @"
PostgreSQL Active Directory synchronization
https://github.com/hanschou/pg_ad_sync

Tool for automatic creating roles (users) in PosgreSQL which is defined in a Windows Active Directory group.

Options:
    -Help
		This help.
	  
    -DropAdRoles
		Default: False
		Drop all roles which has a special commment:
			'Created by pg_ad_sync.'

    -NoCaseRoles
		Default: False
		Do not create roles case sensitive. If roles are created case sensitive one has to logon with the exactly same casing.
		
	-PgHost
		Default: Empty
		Hostname of the PostgreSQL database.
		
	-PgPort
		Default: Blank
		Port number of the PostgreSQL port.
		
	-PgDatabase
		Default: Blank
		Name of the PostgreSQL database.
		
	-PgUser
		Default: Blank
		Name of the PostgreSQL administrator.
		
	-PgPassword
		Default: Blank
		Password for the PostgreSQL administrator.

To get a group from the AD, a group with the same name has be created in PosgreSQL as a role.
The role in PostgreSQL has to have special comment for the script to be recognized.
Example an AD group called "PG-USERS":
  CREATE ROLE "PG-USERS";
  COMMENT ON ROLE "PG-USERS" IS 'This role is in sync with Active Directory.';
Double quote is required as the group name has hyphen in it.

Credentials:
  Username and password for PostgreSQL can be given on command line, in the environment or in credentials file.
  Command line:
	powershell.exe -File pg_ad_sync.ps1 -PgUser postgres -PgPassword p4zzw0rd
  Environment:
	SET PGUSER=postgres
	SET PGPASSWORD=p4zzw0rd
  Credentials file:
	Save the file as: %APPDATA%\postgresql\pgpass.conf
	Content:
	  localhost:5432:template1:postgres:p4zzw0rd

Hint: Get a list of the groups you are member of in the AD.
Invoke from within Powershell:
  ([ADSISEARCHER]"samaccountname=$($env:USERNAME)").Findone().Properties.memberof

Example output:
  CN=PG-ADMIN,OU=Admin,OU=Acme Inc,DC=example,DC=org
  CN=PG-USERS,OU=INF,OU=Acme Inc,DC=example,DC=org
"@
	Exit
}

Remove-Item -Path "*.log"
Get-Date -Format "o" | Add-Content "pg_ad_sync.log"

$psql = "psql.exe"

if ($PgHost) {
	$psql = "$psql --host=$PgHost"
}
if ($PgPort) {
	$psql = "$psql --port=$PgPort"
}
if ($PgDatabase) {
	$psql = "$psql --dbname=$PgDatabase"
}
if ($PgUser) {
	$psql = "$psql --username=$PgUser"
}
if ($PgPassword) {
	$Env:PGPASSWORD="$PgPassword"
}
if (-not (Test-Path Env:PGPASSWORD)) {
	"Error: Environment variable PGPASSWORD and command line parameter '-PgPassword' is not set." | Add-Content "pg_ad_sync.log"
	Exit
}
"PostgreSQL invocation: $psql" | Add-Content "pg_ad_sync.log"

If (Test-Path "pg_ad_sync.tmp.sql") {
    Remove-Item -Path "pg_ad_sync.tmp.sql"
}
if ($DropAdRoles) {
	"Warning, existing roles is dropped." | Add-Content "pg_ad_sync.log"
	$command1 = @"
"SELECT 'DROP ROLE """"' || rolname || '"""";' FROM pg_roles r JOIN pg_shdescription s ON (r.oid=s.objoid) WHERE s.description='Created by pg_ad_sync.' ORDER BY oid;"
"@
	Invoke-Expression "$psql --tuples-only --no-align --command=$command1" | Add-Content "pg_ad_sync.tmp.sql"
	if (0 -ne $LASTEXITCODE) {
		"Error: Code $LASTEXITCODE invoking psql.exe" | Add-Content "pg_ad_sync.log"
		Exit
	}
}

Invoke-Expression "$psql --dbname=postgres --tuples-only --no-align --command=""SELECT rolname FROM pg_roles r JOIN pg_shdescription s ON (r.oid=s.objoid) WHERE s.description='This role is in sync with Active Directory.'""" |
    ForEach-Object {
        $role = $_
        "-- Role: $role" | Add-Content "pg_ad_sync.tmp.sql"
        $search = [adsisearcher][ADSI]""
        $search.Filter = "(&(objectclass=group)(cn=$role))" # LDAP syntax
        $search.FindOne().GetDirectoryEntry() |
            select -ExpandProperty member | # expand to distinguishedname
                ForEach-object {  # for each member in the group
                    $searcher = [adsisearcher]"(distinguishedname=$_)"
                    $member = $searcher.FindOne().Properties.samaccountname
					if (-Not ($member -iMatch "postgres")) {
						if (-Not $NoCaseRoles -Or $member -Match "-") {
							$member = """$member"""
						} else {
							$member = "$member".ToLower()
						}
						"CREATE ROLE $member WITH LOGIN;" | Add-Content "pg_ad_sync.tmp.sql"
						"COMMENT ON ROLE $member IS 'Created by pg_ad_sync.';" | Add-Content "pg_ad_sync.tmp.sql"
						"GRANT ""$role"" TO $member;" | Add-Content "pg_ad_sync.tmp.sql"
					}
                }
    }
if (0 -ne $LASTEXITCODE) {
	"Error: Code $LASTEXITCODE invoking psql.exe" | Add-Content "pg_ad_sync.log"
	Exit
}

Invoke-Expression "$psql --dbname=postgres --echo-queries --file=pg_ad_sync.tmp.sql" | Add-Content "pg_ad_sync.log"
if (0 -ne $LASTEXITCODE) {
	"Error: Code $LASTEXITCODE invoking psql.exe" | Add-Content "pg_ad_sync.log"
	Exit
}

Get-Date -Format "o" | Add-Content "pg_ad_sync.log"
