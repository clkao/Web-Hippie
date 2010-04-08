package Plack::Middleware::Hippie::JSFiles;
use parent 'Plack::App::File';
use Try::Tiny;
use File::ShareDir;

sub root {
    try { File::ShareDir::dist_dir('Plack-Middleware-Hippie') } || 'share';
}

1;
