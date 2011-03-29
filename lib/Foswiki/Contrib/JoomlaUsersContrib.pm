# Module of Foswiki Collaboration Platform, http://Foswiki.org/
#
# Copyright (C) 2006-2010 Sven Dowideit, SvenDowideit@fosiki.com
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

package Foswiki::Contrib::JoomlaUsersContrib;
use vars qw( $VERSION $DB );
$VERSION = '2.0.1';

package Foswiki::Contrib::JoomlaUsersContrib;
use Foswiki::Contrib::DbiContrib;

=pod 

---+ JoomlaUsersContrib singleton to provide access to the database.

this extraction from JoomlaUserMapping was only necessary as foswiki 1.0 called the loginmanager before the mapping was created. 
foswiki 1.1 corrects this but thus makes it difficult to place the DB open in either place

=end

use strict;
use Foswiki::Contrib::DbiContrib;

=pod

---++ ClassMethod getDB( ) -> $object

retrives the joomla DbiContrib obj

=cut


sub getDB {

    $DB = new Foswiki::Contrib::DbiContrib( {
            dsn => $Foswiki::cfg{Plugins}{JoomlaUser}{DBI_dsn},
            dsn_user => $Foswiki::cfg{Plugins}{JoomlaUser}{DBI_username},
            dsn_password => $Foswiki::cfg{Plugins}{JoomlaUser}{DBI_password}
    } );

    return $DB;
}

=begin pod

---++ ClassMethod finish()
close the joomla DbiContrib object

=cut

sub finish {
    if (defined($DB)) {
        $DB->disconnect();
        undef $DB;
    }    
    return;
}

1;
