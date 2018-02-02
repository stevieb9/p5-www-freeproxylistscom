#!/usr/bin/perl
use warnings;
use strict;

use Data::Dumper;
use Test::More;
use WWW::FreeProxyListsCom;

my $p = WWW::FreeProxyListsCom->new(timeout => 10);

eval {
    my $proxies = $p->get_list;

    my $https_count;
    my $total;

    for (@$proxies){
        $total++;
        $https_count++ if $_->{is_https} eq 'true';
    }

    ok $https_count < $total, "HTTPS proxies are less than the total of all";

    my $urls = $p->urls;

    my ($http, $https, $url_total);

    for (@$urls){
        like
            $_,
            qr|^https?://\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d+$|,
            "url $_ is formatted correctly";

        if ($_ =~ /^http[^s]/){
            $http++;
        }
        else {
            $https++;
        }
        $url_total++;
    }

    is $https, $https_count, "urls contain the correct number of https proxies";
    is $http + $https, $total, "the sum of http + https proxies equal total";
    is $url_total, $total, "the num of urls is ok";
};

done_testing();
