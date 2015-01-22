-module(epgsql_wrapper_worker).

-behaviour(gen_server).

-compile([{parse_transform, lager_transform}]).

-include_lib("epgsql/include/pgsql.hrl").

%% API
-export([start_link/1, simpleQuery/1, extendedQuery/2, prepareStatement/3, bindToStatement/3, executeStatement/3,
  closeStatement/1, closePortalOrStatement/2, batchExecuteStatements/1, stop/0]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).

-record(state, { pg_conn = null }).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
start_link(Args) ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, Args, []).

simpleQuery(SQL) ->
  gen_server:call(?SERVER, {simple_query, SQL}, infinity).

extendedQuery(SQL, Params) ->
  gen_server:call(?SERVER, {extended_query, SQL, Params}, infinity).

prepareStatement(Name, SQL, ParamsTypes) ->
  gen_server:call(?SERVER, {prepare_statement, Name, SQL, ParamsTypes}, infinity).

bindToStatement(Statement, PortalName, ParamsVals) ->
  gen_server:call(?SERVER, {bind_to_statement, Statement, PortalName, ParamsVals}, infinity).

executeStatement(Statement, PortalName, MaxRows) ->
  gen_server:call(?SERVER, {exec_statement, Statement, PortalName, MaxRows}, infinity).

batchExecuteStatements(BatchData) ->
  gen_server:call(?SERVER, {batch_exec_statements, BatchData}, infinity).

closeStatement(Statement) ->
  gen_server:call(?SERVER, {close_statement, Statement}, infinity).

closePortalOrStatement(Type, Name) when Type == statement; Type == portal ->
  gen_server:call(?SERVER, {close_statement_or_portal, Type, Name}, infinity);
closePortalOrStatement(_Type, _Name) ->
  {error, badarg}.

stop() ->
  gen_server:call(?SERVER, stop, infinity).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init(Args) ->
  Host = proplists:get_value(host, Args, "localhost"),
  Port = proplists:get_value(port, Args, 5432),
  User = proplists:get_value(user, Args, "user"),
  Pass = proplists:get_value(pass, Args, "pass"),
  Db = proplists:get_value(db, Args, "test"),
  Timeout = proplists:get_value(timeout, Args, 5000),
  {ok, Conn} = pgsql:connect(Host, User, Pass, [{database, Db}, {port, Port}, {timeout, Timeout}]),
  {ok, #state{ pg_conn = Conn}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
handle_call({simple_query, SQL}, _From, State) ->
  QueryRes = pgsql:squery(State#state.pg_conn, SQL),
  Reply = case QueryRes of
    SomeResult when is_list(SomeResult) == true ->
      BatchResultsParser = fun(BatchItem) ->
        case BatchItem of
          {ok, Columns, Rows} ->
            {ok, mapResult(Columns, Rows)};
          {ok, Count, Columns, Rows} ->
            {ok, Count, mapResult(Columns, Rows)};
          _ ->
            BatchItem
        end
      end,
      {ok, batch_res, lists:map(BatchResultsParser, SomeResult)};
    {ok, Columns, Rows} ->
      {ok, mapResult(Columns, Rows)};
    {ok, Count, Columns, Rows} ->
      {ok, Count, mapResult(Columns, Rows)};
    _ ->
      QueryRes
  end,
  {reply, Reply, State};

handle_call({extended_query, SQL, Params}, _From, State) ->
  QueryRes = case Params of
    [] ->
      pgsql:equery(State#state.pg_conn, SQL);
    _ ->
      pgsql:equery(State#state.pg_conn, SQL, Params)
  end,
  Reply = case QueryRes of
    {ok, Columns, Rows} ->
      {ok, mapResult(Columns, Rows)};
    {ok, Count, Columns, Rows} ->
      {ok, Count, mapResult(Columns, Rows)};
    _ ->
      QueryRes
  end,
  {reply, Reply, State};

handle_call({prepare_statement, Name, SQL, ParamsTypes}, _From, State) ->
  Reply = pgsql:parse(State#state.pg_conn, Name, SQL, ParamsTypes),
  {reply, Reply, State};

handle_call({bind_to_statement, Statement, PortalName, ParamsVals}, _From, State) ->
  Reply = pgsql:bind(State#state.pg_conn, Statement, PortalName, ParamsVals),
  {reply, Reply, State};

handle_call({exec_statement, Statement, PortalName, MaxRows}, _From, State) ->
  Reply = pgsql:execute(State#state.pg_conn, Statement, PortalName, MaxRows),
  {reply, Reply, State};

handle_call({batch_exec_statements, BatchData}, _From, State) ->
  Reply = pgsql:execute_batch(State#state.pg_conn, BatchData),
  {reply, Reply, State};

handle_call({close_statement, Statement}, _From, State) ->
  ok = pgsql:close(State#state.pg_conn, Statement),
  Reply = pgsql:sync(State#state.pg_conn),
  {reply, Reply, State};

handle_call({close_statement_or_portal, Type, Name}, _From, State) ->
  ok = pgsql:close(State#state.pg_conn, Type, Name),
  Reply = pgsql:sync(State#state.pg_conn),
  {reply, Reply, State};

handle_call(stop, _From, State) ->
  Reply = pgsql:close(State#state.pg_conn),
  {stop, normal, Reply, State};

handle_call(_Request, _From, State) ->
  {reply, ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
handle_cast(_Request, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info(_Info, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
  ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

mapResult([], _Rows) ->
  [];
mapResult(_Columns, []) ->
  [];
mapResult(Columns, Rows) ->
  ColumnsExtractor = fun(Elem) ->
    Elem#column.name
  end,
  ColsNames = lists:map(ColumnsExtractor, Columns),
  ResultsMapper = fun(Row) ->
    lists:zip(ColsNames, tuple_to_list(Row))
  end,
  lists:map(ResultsMapper, Rows).
