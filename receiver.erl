%% Author: anton
%% Created: 08.01.2013
%% Description: TODO: Add description to receiver
-module(receiver).
-behaviour(gen_server).
-import(util,[log/2]).
%%
%% Include files
%%

%%
%% Exported Functions
%%
%% callbacks für gen_server
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-compile([export_all]).

-record(state, {coordinatorPID, socket}).

%%
%% API Functions
%%
start(CoordinatorPID,Socket) ->
	gen_server:start(?MODULE,[CoordinatorPID, Socket],[]).

init([CoordinatorPID,Socket]) ->
	gen_udp:controlling_process(Socket, self()),
	{ok, #state{coordinatorPID=CoordinatorPID, socket=Socket}}.

terminate(normal, State) ->
	gen_udp:close(State#state.socket),
	log("Receiver wurde beendet").

%%TODO: Slot
handle_cast({udp, _Socket, _IP, _Port, Packet}, State) ->
	log("Paket angekommen"),
	{_,Sec,_} = now(),
	Timestamp = Sec * 1000,
	%50ms - Slotlänge
	%1000ms - Framelänge
	Slot = (Timestamp rem 1000) / 50,
	gen_server:cast(State#state.coordinatorPID,{recieved, Slot, Timestamp, Packet}),
	{noreply, State};

handle_cast(stop, State) ->
  {stop, normal, State};

handle_cast(Any, State) ->
	log("Unbekannte Nachricht: ~p",[Any]),
	{noreply, State}.


%%
%% Local Functions
%%

log(Message) ->
	util:log("Receiver.log",Message).



%% durch gen_server vorgegeben
handle_call(_Request, _From, State) ->
  {reply, ok, State}.

handle_info(_Info, State) ->
  {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.
