%% Author: anton
%% Created: 08.01.2013
%% Description: TODO: Add description to receiver
-module(receiver).
-behaviour(gen_server).
-import(util,[timestamp/0]).
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

-record(state, {coordinatorPID, socket,station}).

%%
%% API Functions
%%
start(CoordinatorPID,Socket,Station) ->
	%log("[~p]Receiver start",[Station]),
	gen_server:start(?MODULE,[CoordinatorPID, Socket,Station],[]).

init([CoordinatorPID,Socket,Station]) ->
	%log("[~p]Receiver init",[Station]),
	{ok, #state{coordinatorPID=CoordinatorPID, socket=Socket, station=Station}}.

terminate(normal, State) ->
	%log("TERMINATING!"),
	gen_udp:close(State#state.socket).
	%log("Receiver wurde beendet").

handle_info({udp, _Socket, _IP, _Port, Packet}, State) ->
	%log("[~p]Paket angekommen",[State#state.station]),
	Timestamp = util:timestamp(),
	gen_server:cast(State#state.coordinatorPID,{recieved, Timestamp, Packet}),
	{noreply, State};
handle_info(_Info, State) ->
  %log("Unknown Info"),
  {noreply, State}.

handle_cast(stop, State) ->
  {stop, normal, State};

handle_cast(Any, State) ->
	%log("Unbekannte Nachricht: ~p",[Any]),
	{noreply, State}.


%%
%% Local Functions
%%

log(Message) ->
	util:log("Receiver.log",Message).
log(Message, Data) ->
	util:log("Receiver.log",Message, Data).


%% durch gen_server vorgegeben
handle_call(_Request, _From, State) ->
  {reply, ok, State}.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.
