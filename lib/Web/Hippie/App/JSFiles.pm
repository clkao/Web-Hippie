package Web::Hippie::App::JSFiles;
use parent 'Plack::App::File';
use Try::Tiny;
use File::ShareDir;

sub root {
    try { File::ShareDir::dist_dir('Web-Hippie') } || 'share';
}

1;
