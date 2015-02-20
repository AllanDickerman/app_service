module AppService
{
    authentication required;
    
    typedef string task_id;
    typedef string app_id;
    typedef string workspace_id;

    typedef mapping<string, string> task_parameters;

    typedef structure {
	string id;
	string label;
	int required;
	string default;
	string desc;
	string type;
	string enum;
	string wstype;
    } AppParameter;

    typedef structure {
	app_id id;
	string script;
	string label;
	string description;
	list<AppParameter> parameters;
    } App;
    
    typedef string task_status;

    typedef structure {
	task_id id;
	app_id app;
	workspace_id workspace;
	task_parameters parameters;

	task_status status;
	string submit_time;
	string start_time;
	string completed_time;

	string stdout_shock_node;
	string stderr_shock_node;

    } Task;

    typedef structure {
	task_id id;
	App app;
	task_parameters parameters;
	float start_time;
	float end_time;
	float elapsed_time;
	string hostname;
	list <tuple<string output_path, string output_id>> output_files;
    } TaskResult;

    funcdef enumerate_apps()
	returns (list<App>);

    funcdef start_app(app_id, task_parameters params, workspace_id workspace)
	returns (Task task);

    funcdef query_tasks(list<task_id> task_ids)
	returns (mapping<task_id, Task task> tasks);

    funcdef query_task_summary() returns (mapping<task_status status, int count> status);

    funcdef enumerate_tasks(int offset, int count)
	returns (list<Task>);
};
