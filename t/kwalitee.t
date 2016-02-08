#!/usr/bin/env perl
use strict;
use warnings;

use Test::More;

eval { require Test::Kwalitee; Test::Kwalitee->import() };

if ($@ || ! $ENV{RELEASE_TESTING}){
    plan( skip_all => 'Test::Kwalitee not installed; skipping' );
}
