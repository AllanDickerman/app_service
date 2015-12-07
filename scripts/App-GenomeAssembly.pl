#
# The Genome Assembly application.
#

use strict;
use Carp;
use Data::Dumper;
use File::Temp;
use File::Basename;
use IPC::Run 'run';

use Bio::KBase::AppService::AppScript;
use Bio::KBase::AuthToken;

#my $ar_run = "/vol/kbase/deployment/bin/ar-run";
#my $ar_get = "/vol/kbase/deployment/bin/ar-get";

my $ar_run = "ar-run";
my $ar_get = "ar-get";
my $ar_filter = "ar-filter";
my $ar_stat = "ar-stat";

my $script = Bio::KBase::AppService::AppScript->new(\&process_reads);

my $rc = $script->run(\@ARGV);

exit $rc;

our $global_ws;
our $global_token;

sub process_reads {
    my($app, $app_def, $raw_params, $params) = @_;

    print "Proc genome ", Dumper($app_def, $raw_params, $params);

    $global_token = $app->token();
    $global_ws = $app->workspace;

    verify_cmd($ar_run) and verify_cmd($ar_get) and verify_cmd($ar_filter);

    my $output_folder = $app->result_folder();
    # my $output_base   = $params->{output_file};
    my $output_name   = "contigs";

    my $recipe = $params->{recipe};
    my @method = ("-r", $recipe) if $recipe;

    my $pipeline = $params->{pipeline};
    print "PIPELINE: $pipeline\n";

    @method = ("-p", parse_pipeline_args($pipeline)) if $pipeline;

    my $tmpdir = File::Temp->newdir();
    # my $tmpdir = File::Temp->newdir( CLEANUP => 0 );

    my @ai_params = parse_input($tmpdir, $params);

    my $out_tmp = "$tmpdir/$output_name";

    my $token = get_token();

    $ENV{ARAST_AUTH_TOKEN} = $token->token;
    $ENV{ARAST_AUTH_USER}  = $token->user_id;

    my @submit_cmd = ($ar_run, @method, @ai_params);
    print STDERR '\@submit_cmd = '. Dumper(\@submit_cmd);


    my @get_cmd = ($ar_get, '-w', '-p');
    my @filter_cmd = ($ar_filter, '-l', 300, '-c', '5'); # > $out_tmp";

    my $submit_out;
    my $submit_err;
    print STDERR "Running @submit_cmd\n";
    my $submit_ok = run(\@submit_cmd, '>', \$submit_out, '2>', \$submit_err);
    $submit_ok or die "Error submitting run. Run command=@submit_cmd, stdout:\n$submit_out\nstderr:\n$submit_err\n";

    print STDERR "Submission returns\n$submit_out\n";
    my($arast_job) = $submit_out =~ /job\s+id:\s+(\d+)/i;

    print STDERR "Submitted job $arast_job, waiting for results\n";
    print STDERR `$ar_stat`;

    print STDERR "Running pull: @get_cmd -j $arast_job | @filter_cmd\n";
    my $pull_ok = run([@get_cmd, "-j", $arast_job], "|",
		      \@filter_cmd, '>', $out_tmp);
    $pull_ok or die "Error retrieving results from job $arast_job\n";

    my $download_ok = run([$ar_get, "-j", $arast_job, "-o", $tmpdir]);
    $download_ok or die "Error downloading results from $arast_job\n";

    my @outputs;

    my $analysis_dir = "$arast_job\_analysis";
    system("cd $tmpdir && zip -r $arast_job\_analysis.zip $analysis_dir");
    push @outputs, ["$tmpdir/$arast_job\_analysis.zip", 'zip'] if -s "$tmpdir/$arast_job\_analysis.zip";

    my ($report) = glob("$tmpdir/$arast_job*report.txt");
    if ($report) {
        system("mv $report $tmpdir/report.txt");
        push @outputs, ["$tmpdir/report.txt", 'txt'];
    }

    my @assemblies = glob("$tmpdir/$arast_job*.fa $tmpdir/$arast_job*.fasta");
    push @outputs, [ $_, 'contigs' ] for @assemblies;

    system("mv $out_tmp $out_tmp.fa");
    push @outputs, ["$out_tmp.fa", 'contigs'];

    for (@outputs) {
	my ($ofile, $type) = @$_;
	if (-f "$ofile") {
            my $filename = basename($ofile);
            print STDERR "Output folder = $output_folder\n";
            print STDERR "Saving $ofile => $output_folder/$filename ...\n";
	    $app->workspace->save_file_to_file("$ofile", {}, "$output_folder/$filename", $type, 1,
					       (-s "$ofile" > 10_000 ? 1 : 0), # use shock for larger files
					       $global_token);
	} else {
	    warn "Missing desired output file $ofile\n";
	}
    }

    # my $ws = get_ws();
    # my $meta;

    # my $result_folder = $app->result_folder();
    # $ws->save_file_to_file("$out_tmp", $meta, "$result_folder/$output_name", 'contigs',
    #                        1, 1, $token);

    undef $global_ws;
    undef $global_token;

    return { arast_job_id => $arast_job };
}

sub parse_pipeline_args {
    my ($pipe) = @_;

    my @chars = split('', $pipe);

    my $qc;        # flag:  in any quotes
    my ($qs, $qd); # flags: in double and single quotes
    my ($beg, $len) = (0, 0);
    my @args;
    for my $c (@chars) {
        $qs = !$qs if $c eq "'";
        $qd = !$qd if $c eq '"';
        if (!$qc && $qs+$qd) {  # entering quotes
            my $arg = clean_arg(substr($pipe, $beg, $len));
            $beg += $len;
            $len = 0;
            push @args, split(/\s+/, $arg) if $arg;
        } elsif ($qc && !($qs+$qd)) { # exiting quotes
            my $arg = clean_arg(substr($pipe, $beg, $len+1));
            $beg += $len+1;
            $len = -1;
            push @args, $arg if $arg;
        }
        $qc = $qs + $qd;
        $len++;
    }

    my $arg = clean_arg(substr($pipe, $beg, $len));
    push @args, split(/\s+/, $arg) if $arg;

    return @args;
}

sub clean_arg {
    my ($arg) = @_;
    return $1 if $arg =~ /^\s*"(.*)"\s*$/;
    return $1 if $arg =~ /^\s*'(.*)'\s*$/;
    $arg =~ s/^\s+//;
    $arg =~ s/\s+$//;
    $arg;
}

sub get_ws {
    return $global_ws;
}

sub get_token {
    return $global_token;
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
    my @ks = qw(insert_size_mean insert_size_std_dev read_orientation_outward);
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
