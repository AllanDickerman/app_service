#
# The Genome Assembly application.
#

use strict;
use Carp;
use Data::Dumper;
use File::Temp;
use File::Basename;

use Bio::KBase::AppService::AppScript;
use Bio::KBase::AuthToken;
use Bio::P3::Workspace::WorkspaceClient;
use Bio::P3::Workspace::WorkspaceClientExt;

#my $ar_run = "/vol/kbase/deployment/bin/ar-run";
#my $ar_get = "/vol/kbase/deployment/bin/ar-get";

my $ar_run = "ar-run";
my $ar_get = "ar-get";

my $script = Bio::KBase::AppService::AppScript->new(\&process_reads);

$script->run(\@ARGV);

sub process_reads {
    my($app_def, $raw_params, $params) = @_;

    print "Proc genome ", Dumper($app_def, $raw_params, $params);

    verify_cmd($ar_run) and verify_cmd($ar_get);

    my $output_path = $params->{output_path};
    my $output_base = $params->{output_file};
    my $output_name = "$output_base.contigs";

    my $recipe = $params->{recipe};
    my $method = "-r $recipe" if $recipe;

    my $tmpdir = File::Temp->newdir();

    my @ai_params = parse_input($tmpdir, $params);

    my $out_tmp = "$tmpdir/$output_name";

    my $token = get_token();

    $ENV{KB_AUTH_TOKEN} = $token->token;
    $ENV{ARAST_AUTH_USER} = $token->user_id;
    $ENV{KB_RUNNING_IN_IRIS} = 1;

    my $cmd = join(" ", @ai_params);
    $cmd = "$ar_run $method $cmd | $ar_get -w -p > $out_tmp";
    print "$cmd\n";

    run($cmd);

    my $ws = get_ws();
    my $meta;

    $ws->save_file_to_file("$out_tmp", $meta, "$output_path/$output_name", undef,
                           1, 1, $token);
}

my $global_ws;
sub get_ws {
    my $ws = $global_ws || Bio::P3::Workspace::WorkspaceClientExt->new();
    $global_ws ||= $ws;
    return $ws;
}

my $global_token;
sub get_token {
    my $token = $global_token || Bio::KBase::AuthToken->new(ignore_authrc => 0);
    $token && $token->validate() or die "No token or invalid token\n";
    $global_token ||= $token;
}
 
my $global_file_count;
sub get_ws_file {
    my ($tmpdir, $id) = @_;
    # return $id;
    my $ws = get_ws();
    my $token = get_token();

    my $base = basename($id);
    my $file = "$tmpdir/$base";
    my $fh;
    open($fh, ">", $file) or die "Cannot open $file for writing: $!";

    print STDERR "GET WS => $tmpdir $base $id\n";
    system("ls -la $tmpdir");

    eval {
	$ws->copy_files_to_handles(1, $token, [[$id, $fh]]);
    };
    if ($@)
    {
	die "ERROR getting file $id\n$@\n";
    }
    close($fh);
    print "$id $file:\n";
    system("ls -la $tmpdir");
             
    return $file;
}

sub parse_input {
    my ($tmpdir, $input) = @_;

    my @params;
    
    my ($pes, $ses, $ref) = ($input->{paired_end_libs}, $input->{single_end_libs}, $input->{reference_assembly});

    for (@$pes) { push @params, parse_pe_lib($tmpdir, $_) }
    for (@$ses) { push @params, parse_se_lib($tmpdir, $_) }
    push @params, parse_ref($tmpdir, $ref) if $ref;

    return @params;
}

sub parse_pe_lib {
    my ($tmpdir, $lib) = @_;
    my @params;
    push @params, "--pair";
    push @params, get_ws_file($tmpdir, $lib->{read1});
    push @params, get_ws_file($tmpdir, $lib->{read2});
    my @ks = qw(insert_size_mean insert_size_std_dev);
    for my $k (@ks) {
        push @params, $k."=".$lib->{$k} if $lib->{$k};
    }
    return @params;
}

sub parse_se_lib {
    my ($tmpdir, $lib) = @_;
    my @params;
    push @params, "--single";
    push @params, get_ws_file($tmpdir, $lib);
    return @params;
}

sub parse_ref {
    my ($tmpdir, $ref) = @_;
    my @params;
    push @params, "--reference";
    push @params, get_ws_file($tmpdir, $ref);
    return @params;
}


sub verify_cmd {
    my ($cmd) = @_;
    system("which $cmd >/dev/null") == 0 or die "Command not found: $cmd\n";
}

sub run { system(@_) == 0 or confess("FAILED: ". join(" ", @_)); }

#-----------------------------------------------------------------------------
#  Read the entire contents of a file or stream into a string.  This command
#  if similar to $string = join( '', <FH> ), but reads the input by blocks.
#
#     $string = slurp_input( )                 # \*STDIN
#     $string = slurp_input(  $filename )
#     $string = slurp_input( \*FILEHANDLE )
#
#-----------------------------------------------------------------------------
sub slurp_input
{
    my $file = shift;
    my ( $fh, $close );
    if ( ref $file eq 'GLOB' )
    {
        $fh = $file;
    }
    elsif ( $file )
    {
        if    ( -f $file )                    { $file = "<$file" }
        elsif ( $_[0] =~ /^<(.*)$/ && -f $1 ) { }  # Explicit read
        else                                  { return undef }
        open $fh, $file or return undef;
        $close = 1;
    }
    else
    {
        $fh = \*STDIN;
    }

    my $out =      '';
    my $inc = 1048576;
    my $end =       0;
    my $read;
    while ( $read = read( $fh, $out, $inc, $end ) ) { $end += $read }
    close $fh if $close;

    $out;
}
