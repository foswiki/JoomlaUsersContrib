# Module of Foswiki Collaboration Platform, http://Foswiki.org/
#
# Copyright (C) 2006-9 Sven Dowideit, SvenDowideit@fosiki.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 3
# of the License, or (at your option) any later version. For
# more details read LICENSE in the root of this distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# As per the GPL, removal of this notice is prohibited.

=begin pod

---+ package Foswiki::Users::JoomlaUserMapping

canonical user_id == id number of jos_user table
login == username column

=cut

package Foswiki::Users::JoomlaUserMapping;
use base 'Foswiki::UserMapping';

use strict;
use Assert;
use Foswiki::UserMapping;
use Foswiki::Users::BaseUserMapping;
use Foswiki::Time;
use Foswiki::ListIterator;
use Foswiki::Contrib::DbiContrib;

use Error qw( :try );

#@Foswiki::Users::JoomlaUserMapping::ISA = qw( Foswiki::Users::BaseUserMapping );

=pod

---++ ClassMethod new( $session ) -> $object

Constructs a new password handler of this type, referring to $session
for any required Foswiki services.

=cut

sub new {
    my ( $class, $session ) = @_;
    my $this =
      bless( $class->SUPER::new( $session, 'JoomlaUserMapping_' ), $class );
    $this->{mapping_id} = 'JoomlaUserMapping_';
    
    $this->{JoomlaOnePointFive} = $Foswiki::cfg{Plugins}{JoomlaUser}{JoomlaVersionOnePointFive};

    $this->{DB} = new Foswiki::Contrib::DbiContrib( {
            dsn => $Foswiki::cfg{Plugins}{JoomlaUser}{DBI_dsn},
            dsn_user => $Foswiki::cfg{Plugins}{JoomlaUser}{DBI_username},
            dsn_password => $Foswiki::cfg{Plugins}{JoomlaUser}{DBI_password}
    } );

    $this->{error} = undef;
    require Digest::MD5;

    $this->{groupCache} = {};
    return $this;
}

=begin pod

---++ ObjectMethod finish()
Break circular references.

Note to developers; please undef *all* fields in the object explicitly,
whether they are references or not. That way this method is "golden
documentation" of the live fields in the object.

=cut

sub finish {
    my $this = shift;
    $this->{DB}->disconnect();
    undef $this->{DB};
    $this->SUPER::finish();
    return;
}

=begin pod

---++ ObjectMethod loginTemplateName () -> $templateFile

Allows UserMappings to come with customised login screens - that should
preferably only over-ride the UI function

Default is "login"

=cut

sub loginTemplateName {
    return 'login.joomla';
}

=pod

---++ ObjectMethod supportsRegistration() -> $boolean

Return true if the UserMapper supports registration (ie can create new users)

Default is *false*

=cut

sub supportsRegistration {
    return 0;    # NO, we don't
}

=begin pod

---++ ObjectMethod handlesUser ( $cUID, $login, $wikiname) -> $boolean

Called by the Foswiki::Users object to determine which loaded mapping
to use for a given user (must be fast).

=cut

sub handlesUser {
    my ( $this, $cUID, $login, $wikiname ) = @_;

    return 1 if ( defined $cUID && $cUID =~ /$this->{mapping_id}.*/ );
    return 1 if ( $cUID     && $this->login2cUID($cUID) );
    return 1 if ( $login    && $this->login2cUID($login) );
    return 1 if ( $wikiname && $this->findUserByWikiName($wikiname) );

#print STDERR "**** Joomla does not handle ".($cUID||'noCUID').", ".($login||'nologin')."";

    return 0;
}

=begin pod

---++ ObjectMethod login2cUID ($login, $dontcheck) -> cUID

Convert a login name to the corresponding canonical user name. The
canonical name can be any string of 7-bit alphanumeric and underscore
characters, and must correspond 1:1 to the login name.
(undef on failure)

(if dontcheck is true, return a cUID for a nonexistant user too - used for registration)

Subclasses *must* implement this method.


=cut

sub login2cUID {
    my ( $this, $login, $dontcheck ) = @_;

    #we ignore $dontcheck as this mapper does not do registration.

    return login2canonical( $this, $login );
}

=pod

---++ ObjectMethod getLoginName ($cUID) -> login

Converts an internal cUID to that user's login
(undef on failure)

Subclasses *must* implement this method.

=cut

sub getLoginName {
    my ( $this, $user ) = @_;
    return canonical2login( $this, $user );
}

=pod

---++ ObjectMethod addUser ($login, $wikiname, $password, $emails) -> cUID

Add a user to the persistant mapping that maps from usernames to wikinames
and vice-versa, via a *canonical user id* (cUID).

$login and $wikiname must be acceptable to $Foswiki::cfg{NameFilter}.
$login must *always* be specified. $wikiname may be undef, in which case
the user mapper should make one up.

This function must return a canonical user id that it uses to uniquely
identify the user. This can be the login name, or the wikiname if they
are all guaranteed unigue, or some other string consisting only of 7-bit
alphanumerics and underscores.

If you fail to create a new user (for eg your Mapper has read only access),
<pre>
    throw Error::Simple('Failed to add user: '.$error);
</pre>
where $error is a descriptive string.

Throws an Error::Simple if user adding is not supported (the default).

=cut

sub addUser {
    #my ( $this, $login, $wikiname ) = @_;

    throw Error::Simple('JoomlaUserMapping does not allow creation of users ');
    return 0;
}

=pod

---++ ObjectMethod removeUser( $user ) -> $boolean

Delete the users entry from this mapper. Throws an Error::Simple if
user removal is not supported (the default).

=cut

sub removeUser {
    throw Error::Simple('JoomlaUserMapping does not allow removeal of users ');
    return 0;
}

=pod

---++ ObjectMethod getWikiName ($cUID) -> wikiname

Map a canonical user name to a wikiname.

Returns the $cUID by default.

=cut

sub getWikiName {
    my ( $this, $user ) = @_;

    #print STDERR "getWikiName($user)?";
    return $Foswiki::cfg{DefaultUserWikiName}
      if ( $user =~ /^$this->{mapping_id}-1$/ );

    my $user_number = $user;
    $user_number =~ s/^$this->{mapping_id}//;
    my $name;
    my $userDataset =
      $this->{DB}->select( 'select name from jos_users gwn where gwn.id = ?',
        $user_number );
    if ( exists $$userDataset[0] ) {
        $name = $$userDataset[0]{name};
    }
    else {

#TODO: examine having the mapper return the truth, and fakeing guest in the core...
#throw Error::Simple(
#   'user_id does not exist: '.$user);
        return $Foswiki::cfg{DefaultUserWikiName};
    }

    #Make sure we're in 'ok' Wiki word territory
    $name =~ s/[^\w]+(\w)/uc($1)/ge;

    #print STDERR "getWikiName($user) == $name";
    return ucfirst($name);
}

=pod

---++ ObjectMethod userExists($cUID) -> $boolean

Determine if the user already exists or not. Whether a user exists
or not is determined by the password manager.

Subclasses *must* implement this method.

=cut

sub userExists {
    my ( $this, $cUID ) = @_;
    return ($this->canonical2login($cUID) ne $Foswiki::cfg{DefaultUserLogin});
}

=pod

---++ ObjectMethod eachUser () -> listIterator of cUIDs

Called from Foswiki::Users. See the documentation of the corresponding
method in that module for details.

Subclasses *must* implement this method.

=cut

sub eachUser {
    my ($this) = @_;
    ASSERT( $this->isa('Foswiki::Users::JoomlaUserMapping') ) if DEBUG;
    my @list = ();

#TODO: this needs to be implemented in terms of a DB iterator that only selects partial results
    my $userDataset = $this->{DB}->select('select id from jos_users');
    for my $row (@$userDataset) {
        push @list, $this->{mapping_id} . $$row{id};
    }

    return new Foswiki::ListIterator( \@list );
}

=pod

---++ ObjectMethod eachGroupMember ($group) ->  Foswiki::ListIterator of cUIDs

Called from Foswiki::Users. See the documentation of the corresponding
method in that module for details.

Subclasses *must* implement this method.

=cut

sub eachGroupMember {
    my $this      = shift;
    my $groupName = shift;    #group_name
    ASSERT( $this->isa('Foswiki::Users::JoomlaUserMapping') ) if DEBUG;
    ASSERT( defined($groupName) ) if DEBUG;

    return new Foswiki::ListIterator( $this->{groupCache}{$groupName} )
      if ( defined( $this->{groupCache}{$groupName} ) );

    my $members = [];

#return [] if ($groupName =~ /Registered/);    #LIMIT it cos most users are resistered

    my $idRowName = 'group_id';
    if ($this->{JoomlaOnePointFive}) {
        $idRowName = 'id';
    }
    my $groupSelectStatement = 'select '.$idRowName.' from jos_core_acl_aro_groups where name = ?';

    my $groupIdDataSet = $this->{DB}->select(
        $groupSelectStatement,
        $groupName );
    if ( exists $$groupIdDataSet[0] ) {
        my $group        = $$groupIdDataSet[0]{$idRowName};
        my $groupDataset = $this->{DB}->select(
            'select aro_id from jos_core_acl_groups_aro_map where group_id = ?',
            $group
        );

        my $userSelectStatement = 'select value from jos_core_acl_aro where aro_id = ?';
        if ($this->{JoomlaOnePointFive}) {
            $userSelectStatement = 'select value from jos_core_acl_aro where id = ?';
        }

        #TODO: re-write with join & map
        for my $row (@$groupDataset) {

            #get rows of users in group
            my $userDataset = $this->{DB}->select(
                $userSelectStatement,
                $$row{aro_id} );
            my $user_id =
              $this->{mapping_id} . $$userDataset[0]{value};    # user_id
            push @{$members}, $user_id;
        }

    }
    $this->{groupCache}{$groupName} = $members;
    return new Foswiki::ListIterator($members);
}

=pod

---++ ObjectMethod isGroup ($user) -> boolean

Called from Foswiki::Users. See the documentation of the corresponding
method in that module for details.

Subclasses *must* implement this method.

=cut

sub isGroup {
    my ( $this, $user ) = @_;

    my $groupSelectStatement = 'select group_id from jos_core_acl_aro_groups where name = ?';
    if ($this->{JoomlaOnePointFive}) {
        $groupSelectStatement = 'select id from jos_core_acl_aro_groups where name = ?';
    }
    my $groupIdDataSet = $this->{DB}->select($groupSelectStatement, $user );
    if ( exists $$groupIdDataSet[0] ) {

        #print STDERR "$user is a GROUP\n";
        return 1;
    }

    #print STDERR "$user is __not__ a GROUP\n";

    #there are no groups that can login.
    return 0;
}

=pod

---++ ObjectMethod eachGroup () -> ListIterator of groupnames

Called from Foswiki::Users. See the documentation of the corresponding
method in that module for details.

Subclasses *must* implement this method.

=cut

sub eachGroup {
    my ($this) = @_;
    _getListOfGroups($this);
    return new Foswiki::ListIterator( \@{ $this->{groupsList} } );
}

=pod

---++ ObjectMethod eachMembership($cUID) -> ListIterator of groups this user is in

Called from Foswiki::Users. See the documentation of the corresponding
method in that module for details.

Subclasses *must* implement this method.

=cut

sub eachMembership {
    my ( $this, $user ) = @_;
    my @groups = ();

    #TODO: reimpl using db
    _getListOfGroups($this);
    my $it = new Foswiki::ListIterator( \@{ $this->{groupsList} } );
    $it->{filter} = sub {
        $this->isInGroup( $user, $_[0] );
    };
    return $it;
}

=pod

---++ ObjectMethod isAdmin( $user ) -> $boolean

True if the user is an admin
   * is $Foswiki::cfg{SuperAdminGroup}
   * is a member of the $Foswiki::cfg{SuperAdminGroup}

=cut

sub isAdmin {
    my ( $this, $user ) = @_;
    my $isAdmin = 0;

    my $sag = $Foswiki::cfg{SuperAdminGroup};
    $isAdmin = $this->isInGroup( $user, $sag );

    return $isAdmin;
}

=pod

---++ ObjectMethod isInGroup ($user, $group, $scanning) -> bool

Called from Foswiki::Users. See the documentation of the corresponding
method in that module for details.

Default is *false*

=cut

sub isInGroup {
    my ( $this, $user, $group, $scanning ) = @_;
    ASSERT($user) if DEBUG;

    #TODO: reimpl using db

    my @users;
    my $it = $this->eachGroupMember($group);
    while ( $it->hasNext() ) {
        my $u = $it->next();
        next if $scanning->{$u};
        $scanning->{$u} = 1;
        return 1 if $u eq $user;
        if ( $this->isGroup($u) ) {
            return 1 if $this->isInGroup( $user, $u, $scanning );
        }
    }
    return 0;
}

=pod

---++ ObjectMethod findUserByEmail( $email ) -> \@users
   * =$email= - email address to look up
Return a list of canonical user names for the users that have this email
registered with the password manager or the user mapping manager.

Returns an empty list by default.

=cut

sub findUserByEmail {
    my $this  = shift;
    my $email = shift;

    if ($email) {
        my $dataset =
          $this->{DB}->select( 'select * from jos_users where email = ?', $email );
        if ( exists $$dataset[0] ) {
            my @userList = ();
            for my $row (@$dataset) {
                push( @userList, $this->{mapping_id} . $$row{id} );
            }
            return \@userList;
        }
        $this->{error} = 'Login invalid';
        return;
    }
    else {
        $this->{error} = 'No user';
        return;
    }
    return;
}

=pod

---++ ObjectMethod getEmails($user) -> @emailAddress

If this is a user, return their email addresses. If it is a group,
return the addresses of everyone in the group.

Duplicates should be removed from the list.

By default, returns the empty list.

=cut

sub getEmails {
    my ( $this, $cUID ) = @_;

    $cUID =~ s/^$this->{mapping_id}//;
    return unless ( $cUID =~ /^\d+$/ );

    if ($cUID) {
        my $dataset =
          $this->{DB}->select( 'select * from jos_users where id = ?', $cUID );
        if ( exists $$dataset[0] ) {
            return ( $$dataset[0]{email} );
        }
        $this->{error} = 'Login invalid';
        return;
    }
    else {
        $this->{error} = 'No user';
        return;
    }
    return;
}

=pod

---++ ObjectMethod setEmails($user, @emails)

Joomla manages all user info, Foswiki does not 'set'

=cut

sub setEmails {
}

=pod

sub setEmails {
    my $this = shift;
    my $user = shift;
    #die unless ($user);

	return 0;
}

=pod

---++ ObjectMethod findUserByWikiName ($wikiname) -> list of cUIDs associated with that wikiname

Called from Foswiki::Users. See the documentation of the corresponding
method in that module for details.

Subclasses *must* implement this method.

=cut

sub findUserByWikiName {
    my $this     = shift;
    my $wikiname = shift;

    if ($wikiname) {
        my $dataset =
          $this->{DB}->select( 'select * from jos_users where name = ?',
            $wikiname );
        if ( exists $$dataset[0] ) {
            my @userList = ();
            for my $row (@$dataset) {
                push( @userList, $this->{mapping_id} . $$row{id} );
            }
            return \@userList;
        }
        $this->{error} = 'Login invalid';
        return;
    }
    else {
        $this->{error} = 'No user';
        return;
    }
    return;
}

=pod

---++ ObjectMethod checkPassword( $userName, $passwordU ) -> $boolean

Finds if the password is valid for the given user.

Returns 1 on success, undef on failure.

Default behaviour is to return 1.

=cut

sub checkPassword {
    my ( $this, $user, $password, $encrypted ) = @_;

   #print STDERR "checkPassword($user, $password, ".($encrypted||'undef').")\n";

    ASSERT( $this->isa('Foswiki::Users::JoomlaUserMapping') ) if DEBUG;

    my $pw = $this->fetchPass($user);

    # $pw will be 0 if there is no pw
    my $salt = '';
    if ( $pw =~ /^(.{32}):(.*)$/ ) {
        $pw   = $1;
        $salt = $2;    #previous versions of joomla did not have a salt.
    }

    my $encryptedPassword;
    if ( ( defined($encrypted) ) && ( $encrypted == 1 ) ) {
        $encryptedPassword = $password;
    }
    else {
        require Digest::MD5;
        $encryptedPassword = Digest::MD5::md5_hex( $password . $salt );
    }

    $this->{error} = undef;

    #print STDERR "checkPassword( $pw && ($encryptedPassword eq $pw) )\n";

    return 1 if ( $pw && ( $encryptedPassword eq $pw ) );

    # pw may validly be '', and must match an unencrypted ''. This is
    # to allow for sysadmins removing the password field in .htpasswd in
    # order to reset the password.
    return 1 if ( $pw eq '' && $password eq '' );

    $this->{error} = 'Invalid user/password';
    return;
}

=pod

---++ ObjectMethod setPassword( $user, $newPassU, $oldPassU ) -> $boolean

If the $oldPassU matches matches the user's password, then it will
replace it with $newPassU.

If $oldPassU is not correct and not 1, will return 0.

If $oldPassU is 1, will force the change irrespective of
the existing password, adding the user if necessary.

Otherwise returns 1 on success, undef on failure.

Default behaviour is to fail.

=cut

sub setPassword {
    my ( $this, $user, $newPassU, $oldPassU ) = @_;
    throw Error::Simple('cannot change user passwords using JoomlaUserMapper');

    return $this->{passwords}
      ->setPassword( $this->getLoginName($user), $newPassU, $oldPassU );
}

=pod

---++ ObjectMethod passwordError( ) -> $string

Returns a string indicating the error that happened in the password handlers
TODO: these delayed errors should be replaced with Exceptions.

returns undef if no error 9the default)

=cut

sub passwordError {
    my $this = shift;

    return $this->{error};
}

##############################################
#internal methods
# Convert a login name to the corresponding canonical user name. The
# canonical name can be any string of 7-bit alphanumeric and underscore
# characters, and must correspond 1:1 to the login name.
sub login2canonical {
    my ( $this, $login ) = @_;

    my $canonical_id = -1;
    unless ( $login eq $Foswiki::cfg{DefaultUserLogin} ) {

#QUESTION: is the login known valid? if so, need to ASSERT that
#QUESTION: why not use the cache to xform if available, and only aske if.. (or is this the case..... DOCCO )
        use bytes;

        # use bytes to ignore character encoding
        #$login =~ s/([^a-zA-Z0-9])/'_'.sprintf('%02d', ord($1))/ge;
        my $userDataset =
          $this->{DB}->select( 'select * from jos_users where username = ?',
            $login );
        if ( exists $$userDataset[0] ) {
            $canonical_id = $$userDataset[0]{id};

            #TODO:ASSERT there is only one..
        }
        else {
            return;
        }
        no bytes;
    }

    $canonical_id = $this->{mapping_id} . $canonical_id;

    return $canonical_id;
}

# See login2 canonical
sub canonical2login {
    my ( $this, $user ) = @_;
    ASSERT($user) if DEBUG;

    $user =~ s/^$this->{mapping_id}//;
    return unless ( $user =~ /^\d+$/ );
    return $Foswiki::cfg{DefaultUserLogin} if ( $user == -1 );

    my $login = $Foswiki::cfg{DefaultUserLogin};
    my $userDataset =
      $this->{DB}->select( 'select username from jos_users c2l where c2l.id = ?',
        $user );
    if ( exists $$userDataset[0] ) {
        $login = $$userDataset[0]{username};
    }
    else {

#TODO: examine having the mapper returnthe truth, and fakeing guest in the core...
#throw Error::Simple(
#   'user_id does not exist: '.$user);
#die "did you call c2l using a login?";
        return $Foswiki::cfg{DefaultUserLogin};
    }
    return $login;
}

# PRIVATE
#QUESTION: this seems to pre-suppose that login can at times validly be == wikiname
sub _cacheUser {
    my ( $this, $wikiname, $login ) = @_;
    ASSERT($wikiname) if DEBUG;

    $login ||= $wikiname;

    my $user = login2canonical( $this, $login );

    #$this->{U2L}->{$user}     = $login;
    $this->{U2W}->{$user}     = $wikiname;
    $this->{L2U}->{$login}    = $user;
    $this->{W2U}->{$wikiname} = $user;

    return $user;
}

# PRIVATE get a list of groups defined in this Foswiki
sub _getListOfGroups {
    my $this = shift;
    ASSERT( ref($this) eq 'Foswiki::Users::JoomlaUserMapping' ) if DEBUG;

    unless ( $this->{groupsList} ) {
        $this->{groupsList} = [];
        my $dataset =
          $this->{DB}->select('select name from jos_core_acl_aro_groups');
        for my $row (@$dataset) {
            my $groupID = $$row{name};
            push @{ $this->{groupsList} }, $groupID;
        }
    }
    return $this->{groupsList};
}

# Map a login name to the corresponding canonical user name. This is used for
# lookups, and should be as fast as possible. Returns undef if no such user
# exists. Called by Foswiki::Users
sub lookupLoginName {
    my ( $this, $login ) = @_;

    return login2canonical( $this, $login );
}

#sub encrypt {
#    my ( $this, $user, $passwd, $fresh ) = @_;
#
#    ASSERT($this->isa( 'Foswiki::Users::JoomlaUserMapping')) if DEBUG;
#
#	my $toEncode= "$passwd";
#	my $ret = Digest::MD5::md5_hex( $toEncode );
#
#print STDERR "encrypt($user, $passwd) => $ret\n";
#
#	return $ret;
#}

sub fetchPass {
    my ( $this, $user ) = @_;
    ASSERT( $this->isa('Foswiki::Users::JoomlaUserMapping') ) if DEBUG;
    #print STDERR "fetchPass($user)\n";

    if ($user) {
        my $dataset =
          $this->{DB}->select( 'select * from jos_users where username = ?',
            $user );

      #Foswiki::Func::writeWarning("$@$dataset");
      #print STDERR "fetchpass got - ".join(', ', keys(%{$$dataset[0]}))."\n";
      #print STDERR "fetchpass got - ".join(', ', values(%{$$dataset[0]}))."\n";
        if ( exists $$dataset[0] ) {

            #print STDERR "fetchPass($user, ".$$dataset[0]{password}.")\n";
            return $$dataset[0]{password};
        }
        $this->{error} = 'Login invalid';
        return 0;
    }
    else {
        $this->{error} = 'No user';
        return 0;
    }
}

sub passwd {
    my ( $this, $user, $newUserPassword, $oldUserPassword ) = @_;
    ASSERT( $this->isa('Foswiki::Users::JoomlaUserMapping') ) if DEBUG;

    return 1;
}

sub deleteUser {
    my ( $this, $user ) = @_;
    ASSERT( $this->isa('Foswiki::Users::JoomlaUserMapping') ) if DEBUG;

    return 1;
}

1;
