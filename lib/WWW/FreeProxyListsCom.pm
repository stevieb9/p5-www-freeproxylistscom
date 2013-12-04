package WWW::FreeProxyListsCom;

use warnings;
use strict;

our $VERSION = '0.003';

use Carp;
use URI;
use WWW::Mechanize;
use HTML::TokeParser::Simple;
use HTML::Entities;
use Devel::TakeHashArgs;

use base 'Class::Data::Accessor';
__PACKAGE__->mk_classaccessors qw(
    error
    mech
    debug
    list
    filtered_list
);

sub new {
    my $self = bless {}, shift;
    get_args_as_hash(\@_, \my %args, { timeout => 30 } )
        or croak $@;

    $args{mech} ||= WWW::Mechanize->new(
        timeout => $args{timeout},
        agent   => 'Mozilla/5.0 (X11; U; Linux x86_64; en-US; rv:1.8.1.12)'
                    .' Gecko/20080207 Ubuntu/7.10 (gutsy) Firefox/2.0.0.12',
    );

    $self->mech( $args{mech} );
    $self->debug( $args{debug} );

    return $self;
}

sub get_list {
    my $self = shift;

    $self->$_(undef) for qw(error list);
    
    get_args_as_hash(\@_, \my %args, {
            type        => 'elite',
            max_pages   => 1,
        }
    ) or croak $@;

    my %page_for = (
        non_anonymous   => 'non-anonymous',
        map { $_ => $_ } qw(
            elite
            anonymous
            https
            standard
            us
            socks
        ),
    );

    exists $page_for{ $args{type} }
        or croak 'Invalid `type` argument was passed to fetch(). '
            . 'Must be one of' . join q|, |, keys %page_for;

    my $mech = $self->mech;
    my $page_type = $page_for{ $args{type} };
    my $uri = URI->new(
        "http://www.freeproxylists.com/$page_type.html"
    );

    $mech->get($uri)->is_success
        or return $self->_set_error($mech,'net');

    $page_type eq 'anonymous'
        and $page_type = 'anon';
    $page_type eq 'non-anonymous'
        and $page_type = 'nonanon';

    # little tweaking to get the URI to the file normally loaded with AJAX
    my @links = map {
        "http://www.freeproxylists.com/load_${page_type}_" .
            ($_->url =~ m|([^/]+$)|)[0]
    } $mech->find_all_links(text_regex => qr/^detailed list #\d+/i);

    $args{max_pages}
        and @links = splice @links, 0, $args{max_pages};

    $self->debug
        and print "Going to fetch data from: \n" . join "\n", @links,'';

    my @proxies;
    for ( @links ) {
        unless ( $mech->get($_)->is_success ) {
            $self->debug 
                and carp 'Network error: ' . $mech->res->status_line;
            next;
        }

        my $list_ref = $self->_parse_list( $mech->res->content )
            or next;

        push @proxies, @$list_ref;
    }

    return $self->list( \@proxies );
}

sub filter {
    my $self = shift;

    $self->$_(undef) for qw(error filtered_list);
    
    get_args_as_hash( \@_, \my %args)
        or croak $@;

    my %valid_filters;
    @valid_filters{ qw(ip  port  is_https  country  last_test  latency) }
    = (1) x 5;

    grep { not exists $valid_filters{$_} } keys %args
        and return $self->_set_error(
            'Invalid filter specified, valid ones are: '.
                join q|, |, keys %valid_filters
        );

    my $list_ref = $self->list
        or return $self->_set_error(
           'Proxy list seems to be undefined, did you call get_list() first?'
        );

    my @filtered;
    foreach my $proxy_ref ( @$list_ref ) {
        my $is_good = 0;
        for ( keys %args ) {
            if ( ref $args{$_} eq 'Regexp' ) {
                $proxy_ref->{$_} =~ /$args{$_}/
                    and $is_good++;
            }
            else {
                $proxy_ref->{$_} eq $args{$_}
                    and $is_good++;
            }
        }

        $is_good == keys %args
            and push @filtered, { %$proxy_ref };
    }
    return $self->filtered_list( \@filtered );
}


sub _parse_list {
    my ( $self, $content ) = @_;

    # EVIL EVIL EVIL!! WEEE \o/
    ( $content ) = $content =~ m|<quote>(.+?)</quote>|s;
    decode_entities $content;

    my $parser = HTML::TokeParser::Simple->new( \$content );

    my %cells;
    @cells{ 1..6 } = qw(ip port is_https latency last_test country);
    my %nav;
    @nav{ qw(get_data level data_cell) } = (0) x 3;

    my @data;
    my %current;
    while ( my $t = $parser->get_token ) {
        if ( $t->is_start_tag('tr') ) {
            @nav{ qw(get_data level) } = (1, 1);
        }
        elsif ( $nav{get_data} == 1 and $t->is_start_tag('td') ) {
            $nav{level} = 2;
            $nav{data_cell}++;
        }
        elsif ( $nav{data_cell} and $t->is_text ) {
            $current{ $cells{ $nav{data_cell} } } = $t->as_is;
        }
        elsif ( $t->is_end_tag('tr') ) {
            @nav{ qw(level get_data data_cell) } = ( 3, 0, 0 );

            next unless keys %current;

            $current{ $_ } = 'N/A'
                for grep { !defined $current{$_} or !length $current{$_} }
                    values %cells;

            push @data, { %current };
            %current = ();
        }
    }

    shift @data; # quick and dirty fix to rid of bad data.
    return \@data;
}

sub _set_error {
    my ( $self, $mech_or_error, $type ) = @_;
    if ( defined $type and $type eq 'net' ) {
        $self->error('Network error: ' . $mech_or_error->res->status_line);
    }
    else {
        $self->error( $mech_or_error );
    }
    return;
}

1;
__END__

=head1 NAME

WWW::FreeProxyListsCom - get proxy lists from http://www.freeproxylists.com

=head1 SYNOPSIS

    use strict;
    use warnings;

    use WWW::FreeProxyListsCom;

    my $prox = WWW::FreeProxyListsCom->new;

    my $ref = $prox->get_list( type => 'non_anonymous' )
        or die $prox->error;

    print "Got a list of " . @$ref . " proxies\nFiltering...\n";

    $ref = $prox->filter( port => qr/(80){1,2}/ );

    print "Filtered list contains: " . @$ref . " proxies\n"
            . join "\n", map( "$_->{ip}:$_->{port}", @$ref), '';

=head1 DESCRIPTION

The module provides interface to fetch proxy server lists from
L<http://www.freeproxylists.com/>

=head1 CONSTRUCTOR

=head2 C<new>

    my $prox = WWW::FreeProxyListCom->new;

    my $prox2 = WWW::FreeProxyListCom->new(
        timeout     => 20, # or 'mech'
        mech        => WWW::Mechanize->new( agent => 'foos', timeout => 20 ),
        debug       => 1,
    );

Bakes up and returns a fresh WWW::FreeProxyListCom object. Takes a few
arguments, all of which are I<optional>. Possible arguments are as follows:

=head3 C<timeout>

    my $prox = WWW::FreeProxyListCom->new( timeout => 10 );

Takes a scalar as a value which is the value that will be passed to
the L<WWW::Mechanize> object to indicate connection timeout in seconds.
B<Defaults to:> C<30> seconds

=head3 C<mech>

    my $prox = WWW::FreeProxyListCom->new(
        mech => WWW::Mechanize->new( agent => '007', timeout => 10 ),
    );

If a simple timeout is not enough for your needs feel free to specify
the C<mech> argument which takes a L<WWW::Mechanize> object as a value.
B<Defaults to:> plain L<WWW::Mechanize> object with C<timeout> argument
set to whatever WWW::FreeProxyListCom's C<timeout> argument
is set to as well as C<agent> argument is set to mimic FireFox.

=head3 C<debug>

    my $prox = WWW::FreeProxyListCom->new( debug => 1 );

When set to a true value will make the object print out some debugging
info. B<Defaults to:> C<0>

=head1 METHODS

=head2 C<get_list>

    my $list_ref = $prox->get_list
        or die $prox->error;

    my $list_ref2 = $prox->get_list(
        type        => 'standard',
        max_pages   => 5,
    ) or die $prox->error;

Instructs the object ot fetch a list of proxies from
L<http://www.freeproxylists.com/> website. On failure returns either
C<undef> or an empty list depending on the context and the reason
for failure will be available via C<error()> method. B<Note:> if request
for a each of the "list" (see C<max_pages> argument below) fails the
C<get_list()> will NOT error out, if you are getting empty proxy lists
try setting C<debug> option on in the constructor and it will carp()
any failures on the "list" gets. On success returns an arrayref of hashrefs,
see C<RETURN VALUE> section below for details. Takes several arguments all
of which are I<optional>. To understand them better you should visit
L<http://www.freeproxylists.com/> first. The possible arguments are
as follows:

=head3 C<type>

    ->get_list( type => 'standard' );

B<Optional>. Specifies the list of proxies to fetch. B<Defaults to:>
C<elite>. Possible arguments are
as follows (valid C<type> values are on the left, corresponding "list" site's
menu link names are on the right):

    elite           => http elite proxies
    anonymous       => http anonymous lists
    non_anonymous   => http non-anonymous
    https           => https (SSL enabled)
    standard        => http standard ports
    us              => us proxies only
    socks           => socks (version 4/5)

=head3 C<max_pages>

    ->get_list( max_pages => 4 );

B<Optional>. Specifies how many "lists" to fetch. In other words, if
you go to list section titled "http elite proxies" you'll see several lists
in the table; the C<max_pages> specifies how many of those lists to fetch.
If C<max_pages> is larger than the number of available lists only the
number of available lists will be fetched. A special value of C<0> indicates
that the object should fetch all available lists for a specified C<type>.
B<Defaults to:> C<1> (which is more than enough).

=head3 RETURN VALUE

    $VAR1 = [
        {
            'country' => 'China',
            'last_test' => '3/15 4:23:14 pm',
            'ip' => '121.15.200.147',
            'latency' => '5115',
            'port' => '80',
            'is_https' => 'true'
        },
    ]

On success C<get_list()> method returns a (possibly empty) arrayref of
"proxy" hashrefs. The hashrefs represent each proxy listed on the proxy
list on the site. Each will contain the following keys (if the value for a
specific key was not found on the site it will be set to C<N/A>):

=over 10

=item ip

The IP address of the proxy

=item port

The port of the proxy

=item country

The country of the proxy

=item last_test

When was the proxy last tested to be alive, this is the "Date checked, UTC"
column on the site.

=item latency

Corresponds to the "Latency" column on the site

=item is_https

Corresponds to "HTTPS" column on the site.

=back

=head2 C<filter>

    my $filtered_list_ref = $prox->filter(
        port        => 80,
        ip          => qr/^120/,
        country     => 'Russia',
        is_https    => 'true',
        last_test   => qr|^3/15|, # march 15's
        latency     => qr/\d{1,2}/,
    );

Must be called after a successfull call to C<get_list()> will croak
otherwise. Takes one or more key/value pairs of arguments which specify
filtering rule. The keys are the same as the keys of "proxy" hashref
in the return value of the C<get_list()> method. Values can be either
simple scalars or regexes (C<qr//>). If value is a regex the corresponding
value in the "proxy" hashref will matched against the regex, otherwise
the C<eq> will be done. Returns an arrayref of "proxy" hashrefs in the
exact same format as C<get_list()> returns except filtered. In other words
calling C<< $prox->filter( port => 80, latency => qr/\d{1,2}/ ) >> will
return only proxies with port number C<80> and for which latency is a two
digit value. On failure returns either C<undef> or an empty list depending on
the context and the reason for the error will be available via C<error()>
method. Although, C<filter()> should not fail if you pass proper filter
arguments and call it after successfull C<get_list()>.

=head2 C<error>

    my $list_ref = $prox->get_list
        or die $prox->error;

When either C<get_list()> or C<filter()> methods fail they will return
either C<undef> or an empty list depending on the context and the reason
for the failure will be available via C<error()> method. Takes no arguments,
returns a human parsable message explaining why C<get_list()> or C<filter()>
failed.

=head2 C<list>

    my $last_list_ref = $prox->list;

Must be called after a successfull call to C<get_list()>. Takes no arugments,
returns the same arrayref of hashrefs last call to C<get_list()> returned.

=head2 C<filtered_list>

    my $last_filtered_list_ref = $prox->filtered_list;

Must be called after a successfull call to C<filter()>. Takes no arugments,
returns the same arrayref of hashrefs last call to C<filter()> returned.

=head2 C<mech>

    my $old_mech = $prox->mech;

    $prox->mech( WWW::Mechanize->new( agent => 'blah' ) );

Returns a L<WWW::Mechanize> object used for fetching proxy lists.
When called with an
optional argument (which must be a L<WWW::Mechanize> object) will use it
in any subsequent C<get_list()> calls.

=head2 C<debug>

    my $old_debug = $prox->debug;

    $prox->debug( 1 );

Returns a currently set debug flag (see C<debug> argument to constructor).
When called with an argument will set the debug flag to the value specified.

=head1 AUTHOR

Zoffix Znet, C<< <zoffix at cpan.org> >>
(L<http://zoffix.com>, L<http://haslayout.net>)

=head1 BUGS

Please report any bugs or feature requests to C<bug-www-freeproxylistscom at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=WWW-FreeProxyListsCom>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc WWW::FreeProxyListsCom

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=WWW-FreeProxyListsCom>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/WWW-FreeProxyListsCom>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/WWW-FreeProxyListsCom>

=item * Search CPAN

L<http://search.cpan.org/dist/WWW-FreeProxyListsCom>

=back

=head1 COPYRIGHT & LICENSE

Copyright 2008 Zoffix Znet, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
