use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'WWW::FreeProxyListsCom',
    license             => 'perl',
    dist_author         => 'Zoffix Znet <zoffix@cpan.org>',
    dist_version_from   => 'lib/WWW/FreeProxyListsCom.pm',
    build_requires => {
        'Test::More' => 0,
    },
    requires => {
        'Carp'                     => 1.04,
        'URI'                      => 1.35,
        'WWW::Mechanize'           => 1.34,
        'HTML::TokeParser::Simple' => 3.15,
        'HTML::Entities'           => 1.35,
        'Devel::TakeHashArgs'      => 0.001,
        'Class::Accessor::Grouped'    => 0,
        'perl' => '5.006',
    },
    configure_requires => { 'Module::Build' => 0 },
    add_to_cleanup      => [ 'WWW-FreeProxyListsCom-*' ],
    create_makefile_pl => 'traditional',
);
if ( $ENV{RELEASE_TESTING} ) {
    system('pod2text lib/WWW/FreeProxyListsCom.pm > README');
}
$builder->create_build_script();
