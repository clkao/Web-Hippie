use strict;
use Test::More tests => 5;

BEGIN { use_ok 'Web::Hippie' }
BEGIN { use_ok 'Web::Hippie::Pipe' }
BEGIN { use_ok 'Web::Hippie::Handle::MXHR' }
BEGIN { use_ok 'Web::Hippie::Handle::WebSocket' }
BEGIN { use_ok 'Web::Hippie::App::JSFiles' }
