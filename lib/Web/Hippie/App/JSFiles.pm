package Web::Hippie::App::JSFiles;
use strict;
use Try::Tiny;
use File::ShareDir;

use parent 'Plack::App::File';

sub root {
    try { File::ShareDir::dist_dir('Web-Hippie') } || 'share';
}

sub files {
    qw(DUI.js
       Stream.js
       hippie.js
       hippie.pipe.js
       jquery.ev.js
       json2.js)
}

1;

__END__

=head1 NAME

Web::Hippie::App::JSFiles - Serve javascript files for Web::Hippie

=head1 SYNOPSIS

  use Web::Hippie::App::JSFiles;
  my $app = Hippie::App::JSFiles->new;

=head1 DESCRIPTION

This PSGI app provides javascript files for Hippie.

=head1 AUTHOR

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

=cut
