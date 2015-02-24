package Bio::KBase::AppService::AppServiceImpl;
use strict;
use Bio::KBase::Exceptions;
# Use Semantic Versioning (2.0.0-rc.1)
# http://semver.org 
our $VERSION = "0.1.0";

=head1 NAME

AppService

=head1 DESCRIPTION



=cut

#BEGIN_HEADER

use JSON::XS;
use MongoDB;
use Data::Dumper;
use Bio::KBase::AppService::Awe;
use Bio::KBase::AppService::Shock;
use Bio::KBase::AppService::Util;
use Bio::KBase::DeploymentConfig;
use File::Slurp;
use UUID;

sub _lookup_task
{
    my($self, $awe, $task_id) = @_;

    my $task;
    my $q = "/job/$task_id";
    print STDERR "_lookup_task: $q\n";
    my ($res, $error) = $awe->GET($q);
    if ($res)
    {
	$task = $self->_awe_to_task($res->{data});
    }
    
    return $task;
}

sub _awe_to_task
{
    my($self, $t) = @_;
    
    my $i = $t->{info};
    my $u = $i->{userattr};
    my $atask = $t->{tasks}->[0];

    my $task = {
	id => $t->{id},
	app => $u->{app_id},
	workspace => $u->{workspace},
	parameters => decode_json($u->{parameters}),
	status => $t->{state},
	submit_time => $i->{submittime},
	start_time => $i->{startedtime},
	completed_time => $i->{completedtime},
	stdout_shock_node => $self->_lookup_output($atask, "stdout.txt"),
	stderr_shock_node => $self->_lookup_output($atask, "stderr.txt"),
	awe_stdout_shock_node => $self->_lookup_output($atask, "awe_stdout.txt"),
	awe_stderr_shock_node => $self->_lookup_output($atask, "awe_stderr.txt"),
	
    };
    return $task;
}

sub _lookup_output
{
    my($self, $atask, $filename) = @_;
    my $outputs = $atask->{outputs};
    my $file = $outputs->{$filename};
    # print STDERR Dumper($atask);
    if ($file)
    {
	my $h = $file->{host};
	my $n = $file->{node};
	if ($h && $n && $n ne '-')
	{
	    return "$h/node/$n";
	}
    }
    return "";
}
#END_HEADER

sub new
{
    my($class, @args) = @_;
    my $self = {
    };
    bless $self, $class;
    #BEGIN_CONSTRUCTOR

    my $cfg = Bio::KBase::DeploymentConfig->new($ENV{KB_SERVICE_NAME} || "AppService");
    my $awe_server = $cfg->setting("awe-server");
    $self->{awe_server} = $awe_server;
    my $shock_server = $cfg->setting("shock-server");
    $self->{shock_server} = $shock_server;
    my $app_dir = $cfg->setting("app-directory");
    $self->{app_dir} = $app_dir;

    $self->{awe_mongo_db} = $cfg->setting("awe-mongo-db") || "AWEDB";
    $self->{awe_mongo_host} = $cfg->setting("awe-mongo-host") || "localhost";
    $self->{awe_mongo_port} = $cfg->setting("awe-mongo-port") || 27017;
    $self->{awe_clientgroup} = $cfg->setting("awe-clientgroup") || "";
    

    $self->{util} = Bio::KBase::AppService::Util->new($self);
	
    #END_CONSTRUCTOR

    if ($self->can('_init_instance'))
    {
	$self->_init_instance();
    }
    return $self;
}

=head1 METHODS



=head2 enumerate_apps

  $return = $obj->enumerate_apps()

=over 4

=item Parameter and return types

=begin html

<pre>
$return is a reference to a list where each element is an App
App is a reference to a hash where the following keys are defined:
	id has a value which is an app_id
	script has a value which is a string
	label has a value which is a string
	description has a value which is a string
	parameters has a value which is a reference to a list where each element is an AppParameter
app_id is a string
AppParameter is a reference to a hash where the following keys are defined:
	id has a value which is a string
	label has a value which is a string
	required has a value which is an int
	default has a value which is a string
	desc has a value which is a string
	type has a value which is a string
	enum has a value which is a string
	wstype has a value which is a string

</pre>

=end html

=begin text

$return is a reference to a list where each element is an App
App is a reference to a hash where the following keys are defined:
	id has a value which is an app_id
	script has a value which is a string
	label has a value which is a string
	description has a value which is a string
	parameters has a value which is a reference to a list where each element is an AppParameter
app_id is a string
AppParameter is a reference to a hash where the following keys are defined:
	id has a value which is a string
	label has a value which is a string
	required has a value which is an int
	default has a value which is a string
	desc has a value which is a string
	type has a value which is a string
	enum has a value which is a string
	wstype has a value which is a string


=end text



=item Description



=back

=cut

sub enumerate_apps
{
    my $self = shift;

    my $ctx = $Bio::KBase::AppService::Service::CallContext;
    my($return);
    #BEGIN enumerate_apps
    $return = [];

    push(@$return, $self->{util}->enumerate_apps());
    
    #END enumerate_apps
    my @_bad_returns;
    (ref($return) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"return\" (value was \"$return\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to enumerate_apps:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'enumerate_apps');
    }
    return($return);
}




=head2 start_app

  $task = $obj->start_app($app_id, $params, $workspace)

=over 4

=item Parameter and return types

=begin html

<pre>
$app_id is an app_id
$params is a task_parameters
$workspace is a workspace_id
$task is a Task
app_id is a string
task_parameters is a reference to a hash where the key is a string and the value is a string
workspace_id is a string
Task is a reference to a hash where the following keys are defined:
	id has a value which is a task_id
	app has a value which is an app_id
	workspace has a value which is a workspace_id
	parameters has a value which is a task_parameters
	status has a value which is a task_status
	submit_time has a value which is a string
	start_time has a value which is a string
	completed_time has a value which is a string
	stdout_shock_node has a value which is a string
	stderr_shock_node has a value which is a string
task_id is a string
task_status is a string

</pre>

=end html

=begin text

$app_id is an app_id
$params is a task_parameters
$workspace is a workspace_id
$task is a Task
app_id is a string
task_parameters is a reference to a hash where the key is a string and the value is a string
workspace_id is a string
Task is a reference to a hash where the following keys are defined:
	id has a value which is a task_id
	app has a value which is an app_id
	workspace has a value which is a workspace_id
	parameters has a value which is a task_parameters
	status has a value which is a task_status
	submit_time has a value which is a string
	start_time has a value which is a string
	completed_time has a value which is a string
	stdout_shock_node has a value which is a string
	stderr_shock_node has a value which is a string
task_id is a string
task_status is a string


=end text



=item Description



=back

=cut

sub start_app
{
    my $self = shift;
    my($app_id, $params, $workspace) = @_;

    my @_bad_arguments;
    (!ref($app_id)) or push(@_bad_arguments, "Invalid type for argument \"app_id\" (value was \"$app_id\")");
    (ref($params) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"params\" (value was \"$params\")");
    (!ref($workspace)) or push(@_bad_arguments, "Invalid type for argument \"workspace\" (value was \"$workspace\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to start_app:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'start_app');
    }

    my $ctx = $Bio::KBase::AppService::Service::CallContext;
    my($task);
    #BEGIN start_app

    my $json = JSON::XS->new->pretty(1);

    #
    # Create a new workflow for this task.
    #

    my $app = $self->{util}->find_app($app_id);

    if (!$app)
    {
	die "Could not find app for id $app_id\n";
    }

    my $awe = Bio::KBase::AppService::Awe->new($self->{awe_server}, $ctx->token);

    my $param_str = $json->encode($params);

    #
    # Create an identifier we can use to match the Shock nodes we create for this
    # job with the job itself.
    #
    my($task_file_uuid, $task_file_id);
    UUID::generate($task_file_uuid);
    UUID::unparse($task_file_uuid, $task_file_id);
    
    my $userattr = {
	app_id => $app_id,
	parameters => $param_str,
	workspace => $workspace,
	task_file_id => $task_file_id,
    };
	
    my $job = $awe->create_job_description(pipeline => 'AppService',
					   name => $app_id,
					   project => 'AppService',
					   user => $ctx->user_id,
					   clientgroups => $self->{awe_clientgroup},
					   userattr => $userattr,
					   priority => 2,
					  );

    my $shock = Bio::KBase::AppService::Shock->new($self->{shock_server}, $ctx->token);
    $shock->tag_nodes(task_file_id => $task_file_id,
		      app_id => $app_id);
    my $params_node_id = $shock->put_file_data($param_str, "params");

    my $app_node_id = $shock->put_file_data($json->encode($app), "app");

    my $app_file = $awe->create_job_file("app", $shock->server, $app_node_id);
    my $params_file = $awe->create_job_file("params", $shock->server, $params_node_id);

    my $stdout_file = $awe->create_job_file("stdout.txt", $shock->server);
    my $stderr_file = $awe->create_job_file("stderr.txt", $shock->server);
    
    my $awe_stdout_file = $awe->create_job_file("awe_stdout.txt", $shock->server);
    my $awe_stderr_file = $awe->create_job_file("awe_stderr.txt", $shock->server);
    

    my $task_userattr = {};
    my $task_id = $job->add_task($app->{script},
				 $app->{script},
				 join(" ",
				      $app_file->in_name, $params_file->in_name,
				      $stdout_file->name, $stderr_file->name),
				 [],
				 [$app_file, $params_file],
				 [$stdout_file, $stderr_file, $awe_stdout_file, $awe_stderr_file],
				 undef,
				 undef,
				 $task_userattr,
				);

    print STDERR Dumper($job);

    my $task_id = $awe->submit($job);

    $task = $self->_lookup_task($awe, $task_id);
    #END start_app
    my @_bad_returns;
    (ref($task) eq 'HASH') or push(@_bad_returns, "Invalid type for return variable \"task\" (value was \"$task\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to start_app:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'start_app');
    }
    return($task);
}




=head2 query_tasks

  $tasks = $obj->query_tasks($task_ids)

=over 4

=item Parameter and return types

=begin html

<pre>
$task_ids is a reference to a list where each element is a task_id
$tasks is a reference to a hash where the key is a task_id and the value is a Task
task_id is a string
Task is a reference to a hash where the following keys are defined:
	id has a value which is a task_id
	app has a value which is an app_id
	workspace has a value which is a workspace_id
	parameters has a value which is a task_parameters
	status has a value which is a task_status
	submit_time has a value which is a string
	start_time has a value which is a string
	completed_time has a value which is a string
	stdout_shock_node has a value which is a string
	stderr_shock_node has a value which is a string
app_id is a string
workspace_id is a string
task_parameters is a reference to a hash where the key is a string and the value is a string
task_status is a string

</pre>

=end html

=begin text

$task_ids is a reference to a list where each element is a task_id
$tasks is a reference to a hash where the key is a task_id and the value is a Task
task_id is a string
Task is a reference to a hash where the following keys are defined:
	id has a value which is a task_id
	app has a value which is an app_id
	workspace has a value which is a workspace_id
	parameters has a value which is a task_parameters
	status has a value which is a task_status
	submit_time has a value which is a string
	start_time has a value which is a string
	completed_time has a value which is a string
	stdout_shock_node has a value which is a string
	stderr_shock_node has a value which is a string
app_id is a string
workspace_id is a string
task_parameters is a reference to a hash where the key is a string and the value is a string
task_status is a string


=end text



=item Description



=back

=cut

sub query_tasks
{
    my $self = shift;
    my($task_ids) = @_;

    my @_bad_arguments;
    (ref($task_ids) eq 'ARRAY') or push(@_bad_arguments, "Invalid type for argument \"task_ids\" (value was \"$task_ids\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to query_tasks:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'query_tasks');
    }

    my $ctx = $Bio::KBase::AppService::Service::CallContext;
    my($tasks);
    #BEGIN query_tasks

    my $awe = Bio::KBase::AppService::Awe->new($self->{awe_server}, $ctx->token);

    $tasks = {};

    for my $task_id (@$task_ids)
    {
	my ($res, $error) = $awe->job($task_id);
	if ($res)
	{
	    my $task = $self->_awe_to_task($res);
	    $tasks->{$task_id} = $task;
	}
    }

    #END query_tasks
    my @_bad_returns;
    (ref($tasks) eq 'HASH') or push(@_bad_returns, "Invalid type for return variable \"tasks\" (value was \"$tasks\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to query_tasks:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'query_tasks');
    }
    return($tasks);
}




=head2 query_task_summary

  $status = $obj->query_task_summary()

=over 4

=item Parameter and return types

=begin html

<pre>
$status is a reference to a hash where the key is a task_status and the value is an int
task_status is a string

</pre>

=end html

=begin text

$status is a reference to a hash where the key is a task_status and the value is an int
task_status is a string


=end text



=item Description



=back

=cut

sub query_task_summary
{
    my $self = shift;

    my $ctx = $Bio::KBase::AppService::Service::CallContext;
    my($status);
    #BEGIN query_task_summary

    #
    # Summarize counts of tasks of each type for this user.
    #
    # Query mongo for the types available, then count.
    #

    my $mongo = MongoDB::MongoClient->new(host => $self->{awe_mongo_host}, port => $self->{awe_mongo_port});
    my $db = $mongo->get_database($self->{awe_mongo_db});
    my $col = $db->get_collection("Jobs");

    my $states = $db->run_command( [ distinct => "Jobs", key => "state", query => { 'info.user' => $ctx->user_id } ] );

    $status = {};

    for my $state (@{$states->{values}})
    {
	next if $state eq 'deleted';

	my $n = $col->find({"info.user" =>  $ctx->user_id, state => $state, "info.pipeline" => "AppService"})->count();
	$status->{$state} = $n;
    }

    undef $col;
    undef $db;
    undef $mongo;
    
    #END query_task_summary
    my @_bad_returns;
    (ref($status) eq 'HASH') or push(@_bad_returns, "Invalid type for return variable \"status\" (value was \"$status\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to query_task_summary:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'query_task_summary');
    }
    return($status);
}




=head2 enumerate_tasks

  $return = $obj->enumerate_tasks($offset, $count)

=over 4

=item Parameter and return types

=begin html

<pre>
$offset is an int
$count is an int
$return is a reference to a list where each element is a Task
Task is a reference to a hash where the following keys are defined:
	id has a value which is a task_id
	app has a value which is an app_id
	workspace has a value which is a workspace_id
	parameters has a value which is a task_parameters
	status has a value which is a task_status
	submit_time has a value which is a string
	start_time has a value which is a string
	completed_time has a value which is a string
	stdout_shock_node has a value which is a string
	stderr_shock_node has a value which is a string
task_id is a string
app_id is a string
workspace_id is a string
task_parameters is a reference to a hash where the key is a string and the value is a string
task_status is a string

</pre>

=end html

=begin text

$offset is an int
$count is an int
$return is a reference to a list where each element is a Task
Task is a reference to a hash where the following keys are defined:
	id has a value which is a task_id
	app has a value which is an app_id
	workspace has a value which is a workspace_id
	parameters has a value which is a task_parameters
	status has a value which is a task_status
	submit_time has a value which is a string
	start_time has a value which is a string
	completed_time has a value which is a string
	stdout_shock_node has a value which is a string
	stderr_shock_node has a value which is a string
task_id is a string
app_id is a string
workspace_id is a string
task_parameters is a reference to a hash where the key is a string and the value is a string
task_status is a string


=end text



=item Description



=back

=cut

sub enumerate_tasks
{
    my $self = shift;
    my($offset, $count) = @_;

    my @_bad_arguments;
    (!ref($offset)) or push(@_bad_arguments, "Invalid type for argument \"offset\" (value was \"$offset\")");
    (!ref($count)) or push(@_bad_arguments, "Invalid type for argument \"count\" (value was \"$count\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to enumerate_tasks:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'enumerate_tasks');
    }

    my $ctx = $Bio::KBase::AppService::Service::CallContext;
    my($return);
    #BEGIN enumerate_tasks

    my $awe = Bio::KBase::AppService::Awe->new($self->{awe_server}, $ctx->token);

    $return = [];

    #
    # TODO: paging of requests
    #

    my $q = "/job?query&info.user=" . $ctx->user_id . "&info.pipeline=AppService&limit=$count&offset=$offset";
    print STDERR "Query tasks: $q\n";
    my ($res, $error) = $awe->GET($q);
    if ($res)
    {
	for my $t (@{$res->{data}})
	{
	    my $r = $self->_awe_to_task($t);
	    push(@$return, $r);
	}
    }
    else
    {
	die "Query failed: $error\n";
    }

    #END enumerate_tasks
    my @_bad_returns;
    (ref($return) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"return\" (value was \"$return\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to enumerate_tasks:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'enumerate_tasks');
    }
    return($return);
}




=head2 version 

  $return = $obj->version()

=over 4

=item Parameter and return types

=begin html

<pre>
$return is a string
</pre>

=end html

=begin text

$return is a string

=end text

=item Description

Return the module version. This is a Semantic Versioning number.

=back

=cut

sub version {
    return $VERSION;
}

=head1 TYPES



=head2 task_id

=over 4



=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 app_id

=over 4



=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 workspace_id

=over 4



=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 task_parameters

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the key is a string and the value is a string
</pre>

=end html

=begin text

a reference to a hash where the key is a string and the value is a string

=end text

=back



=head2 AppParameter

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is a string
label has a value which is a string
required has a value which is an int
default has a value which is a string
desc has a value which is a string
type has a value which is a string
enum has a value which is a string
wstype has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is a string
label has a value which is a string
required has a value which is an int
default has a value which is a string
desc has a value which is a string
type has a value which is a string
enum has a value which is a string
wstype has a value which is a string


=end text

=back



=head2 App

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is an app_id
script has a value which is a string
label has a value which is a string
description has a value which is a string
parameters has a value which is a reference to a list where each element is an AppParameter

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is an app_id
script has a value which is a string
label has a value which is a string
description has a value which is a string
parameters has a value which is a reference to a list where each element is an AppParameter


=end text

=back



=head2 task_status

=over 4



=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 Task

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is a task_id
app has a value which is an app_id
workspace has a value which is a workspace_id
parameters has a value which is a task_parameters
status has a value which is a task_status
submit_time has a value which is a string
start_time has a value which is a string
completed_time has a value which is a string
stdout_shock_node has a value which is a string
stderr_shock_node has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is a task_id
app has a value which is an app_id
workspace has a value which is a workspace_id
parameters has a value which is a task_parameters
status has a value which is a task_status
submit_time has a value which is a string
start_time has a value which is a string
completed_time has a value which is a string
stdout_shock_node has a value which is a string
stderr_shock_node has a value which is a string


=end text

=back



=head2 TaskResult

=over 4



=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is a task_id
app has a value which is an App
parameters has a value which is a task_parameters
start_time has a value which is a float
end_time has a value which is a float
elapsed_time has a value which is a float
hostname has a value which is a string
output_files has a value which is a reference to a list where each element is a reference to a list containing 2 items:
0: (output_path) a string
1: (output_id) a string


</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is a task_id
app has a value which is an App
parameters has a value which is a task_parameters
start_time has a value which is a float
end_time has a value which is a float
elapsed_time has a value which is a float
hostname has a value which is a string
output_files has a value which is a reference to a list where each element is a reference to a list containing 2 items:
0: (output_path) a string
1: (output_id) a string



=end text

=back



=cut

1;
