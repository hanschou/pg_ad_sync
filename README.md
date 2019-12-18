PostgreSQL Active Directory synchronization
===========================================

Tool for automatic creating roles (users) in PosgreSQL which is defined in a 
Windows Active Directory group.

By using LDAP or SSPI for Single-Sign-On (SSO) the access control and password
change is not related to PostgreSQL but is handled by Windows Active Directory (AD).

One problem remain unsolved so far: Users who will connect to PostgreSQL 
needs to have a role defined in PostgreSQL before hand.

Example
-------

A group is defined in the AD with the name *PG_USERS*.
The group has two members *ALICE* and *BOB* and
they want to connect to the PostgreSQL
database *INVENTORY*.

First the *pg_hba.conf* has to be configured to look up
users in the AD by using either LDAP or SSPI.

Then a new roles has to be created in PostgreSQL with
the name *PG_USERS*. This script should in some way be 
told to look up members of the role in the list of groups
in the AD. This is done by giving the role a special comment:

   *This role is in sync with Active Directory.*

This script first look up all roles having this special comment.
Then it look up the same role name *PG_USERS* in the AD
and get all the members this group has.
Then it creates all the users as roles in PostgreSQL
(without password) and grant them the role *PG_USERS*.

The role *PG_USERS* is granted access to the database *INVENTORY*
or the role is simply the owner of the database.

Steps to create the roles
-------------------------

1. In PostgreSQL, get list of roles with a special comment
2. Look up the role name as a group name in the AD
3. Get the member of the AD group
4. Create the members as roles in PostgreSQL

Task Scheduler
--------------

The script *pg_ad_sync* has to be executed each time there
is a change in:

1. A new role/group is created in PostgreSQL and the AD
2. A new member is added to the group in the AD
3. A member is removed from the group in the AD
