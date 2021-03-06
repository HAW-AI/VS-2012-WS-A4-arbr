%% Author: anton
%% Created: 08.01.2013
%% Description: TODO: Add description to datasource
-module(datasource).
-behaviour(gen_server).

%%
%% Include files
%%

%%
%% Exported Functions
%%

%% callbacks f�r gen_server
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).
-compile([export_all]).


-record(state,{pollPID, value=""}).
%%
%% API Functions
%%
start() ->
	%log("Datasource wurde gestartet"),
	gen_server:start(?MODULE,[],[]).

init(_Args) ->
	MyPid = self(),
	PollPID = spawn(fun() -> poll(MyPid) end),
	register(dq, self()),
	{ok, #state{pollPID=PollPID}}.

poll(DatasourcePID) ->
	case io:get_chars("", 24) of
		eof ->
			%log("EOF erreicht"),
			exit(normal);
		Value -> 
			%log("Value:,~p",[Value]),
			gen_server:cast(DatasourcePID, {newvalue,Value}),
			poll(DatasourcePID)
	end.

handle_cast({newvalue, Value}, State) ->
	%%log("Neue Nachricht aus der Java-Datenquelle: [~p]",[Value]),
	{noreply, State#state{value=Value}};

handle_cast({get_next_value, SenderPID}, State) ->
	%log("Der Sender hat die n�chste Nachricht angefordert"),
	%% sender wird als final state machine implementiert
	%log("N�chste Nachricht ist: ~p",[State#state.value]),
	gen_fsm:send_event(SenderPID, {message, State#state.value}),
	{noreply, State#state{value=""}};

handle_cast(stop, State) ->
  {stop, normal, State};

handle_cast(Any, State) ->
	%log("Unbekannte Nachricht: ~p",[Any]),
	{noreply, State}.

terminate(normal, State) ->
  exit(State#state.pollPID, normal),
  ok.

%% durch gen_server vorgegeben
handle_call(_Request, _From, State) ->
  {reply, ok, State}.

handle_info(_Info, State) ->
  {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.


%%
%% Local Functions
%%

log(Message) ->
	util:log("Datasource.log",Message).
log(Message, Data) ->
	util:log("Datasource.log",Message, Data).
