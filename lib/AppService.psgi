use Bio::KBase::AppService::AppServiceImpl;

use Bio::KBase::AppService::Service;
use Plack::Middleware::CrossOrigin;



my @dispatch;

{
    my $obj = Bio::KBase::AppService::AppServiceImpl->new;
    push(@dispatch, 'AppService' => $obj);
}


my $server = Bio::KBase::AppService::Service->new(instance_dispatch => { @dispatch },
				allow_get => 0,
			       );

my $handler = sub { $server->handle_input(@_) };

$handler = Plack::Middleware::CrossOrigin->wrap( $handler, origins => "*", headers => "*");
