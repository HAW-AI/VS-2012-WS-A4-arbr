%% Author: anton
%% Created: 08.01.2013
%% Description: TODO: Add description to datasource
-module(datasource).
-import(util, [log/2]).
%%
%% Include files
%%

%%
%% Exported Functions
%%
-export([]).
-compile([export_all]).
-record(state,{pollPID, value=""}).
%%
%% API Functions
%%
start() ->
	log("Datasource wurde gestartet"),
	gen_server:start(?MODULE,[],[]).

init(_Args) ->
	PollPID = spawn(fun() -> poll(self()) end),
	{ok, #state{pollPID=PollPID}}.

poll(DatasourcePID) ->
	log("hm"),
	case io:get_chars("", 24) of
		eof ->
			log("EOF erreicht"),
			exit(normal);
		Value -> 
			gen_server:cast(DatasourcePID, {input,Value}),
			poll(DatasourcePID)
	end.

handle_cast({input, Value}, State) ->
	log("Neue Nachricht aus der Java-Datenquelle: "++Value),
	{noreply, State#state{value=Value}};

handle_cast({get_data, PID}, State) ->
	log("Der Sender hat die nächste Nachricht angefordert"),
	%% sender wird als final state machine implementiert
	gen_fsm:send_event(PID, {input, State#state.value}),
	{noreply, State#state{value=""}};

handle_cast(stop, State) ->
  {stop, normal, State};

handle_cast(Any, State) ->
	log("Unbekannte Nachricht: ~p",[Any]),
	{noreply, State}.

terminate(_Reason, State) ->
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
