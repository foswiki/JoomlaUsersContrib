package JoomlaUsersContribSuite;

use Test::Unit::TestSuite;
our @ISA = qw( Test::Unit::TestSuite );

sub name { 'JoomlaUsersContribSuite' }

sub include_tests { qw(JoomlaUsersContribTests) }

1;
