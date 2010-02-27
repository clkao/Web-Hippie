sub author_tests  { }
sub readme_from   { }
sub auto_set_repository { }

use inc::Module::Install;
name 'Plack-Middleware-Hippie';
all_from 'lib/Plack/Middleware/Hippie.pm';
readme_from 'lib/Plack/Middleware/Hippie.pm';
build_requires 'Test::More';
use_test_base;
auto_include_deps;
author_tests('xt');
auto_set_repository;
WriteAll;
