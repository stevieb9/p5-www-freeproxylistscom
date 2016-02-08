#!/usr/bin/perl
use warnings;
use strict;

use Test::More;

BEGIN {
    use_ok('WWW::FreeProxyListsCom');
};

my $o = WWW::FreeProxyListsCom->new(url => '');

SKIP: {
    eval { my $list_ref = $o->get_list(type => 'elite'); };

    if ($@) { 
        skip 'errored out expectedly', 1;
    }
};

done_testing();
