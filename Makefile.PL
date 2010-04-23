sub author_tests  { }
sub readme_from   { }
sub auto_set_repository { }

use inc::Module::Install;
name 'Web-Hippie';
all_from 'lib/Web/Hippie.pm';
readme_from 'lib/Web/Hippie.pm';
build_requires 'Test::More';
test_requires 'Test::Requires';
requires 'Plack';
requires 'AnyMQ' => '0.30';
requires 'HTTP::Date';

install_share 'share';

auto_include_deps;
author_tests('xt');
auto_set_repository;
WriteAll;
