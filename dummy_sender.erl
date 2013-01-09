%% Author: anton
%% Created: 09.01.2013
%% Description: TODO: Add description to dummy_sender
-module(dummy_sender).

%%
%% Include files
%%
-import(util, [log/2, timestamp/0, time_till_slot/1]).

%% gen_fsm requires explicit export of his required functions
-export([slot_received/2,start/0,init/1, handle_sync_event/4, handle_info/3, code_change/4, terminate/3, handle_event/3]).
-compile([export_all]).
-behaviour(gen_fsm).
%%
%% Exported Functions
%%
-export([]).
-record( state, {datasource,slot,message}).
%%
%% API Functions
%%
start()->
  gen_fsm:start( ?MODULE, [], [] ).
init([]) ->
	register(ds, self()),
  { ok, Datasource } = datasource:start(),
	log("Nachricht an DQ gesendet"),
	gen_server:cast(dq,{newvalue,"abc"}),
	gen_server:cast( Datasource, {get_next_value, self() }),
  { ok, slot_received, #state{ datasource=Datasource,slot="",message=""}}.

slot_received({ slot, Slot }, State) ->
  gen_server:cast( State#state.datasource, {get_next_value, self() }),
  log("Anfrage gesendet"),
  {next_state, message_received, State#state{ slot=Slot } }.

message_received({ message, Message }, State) ->
	log("Nachricht emofangen"),
  log(atom_to_list(message)),
  { next_state, next_slot_received, State#state{ message=Message} }.

%%
%% Local Functions
%%

handle_event(stop, _StateName, State) ->
  utility:log("Sender wird ausgeschaltet"),
  {stop, normal, State}.

terminate( _StateName, _StateData, State) ->
	gen_server:cast(State#state.datasource, stop),
	ok.

log(Message) ->
	util:log( "DummySender.log", Message ).

%% gen_fsm API requirements
state_name( _Event, _From, State ) ->
  {reply, ok, state_name, State}.

handle_sync_event( _Event, _From, StateName, State ) ->
  {reply, ok, StateName, State}.

handle_info( _Info, StateName, State ) ->
  {noreply, StateName, State}.

code_change( _OldVsn, StateName, State, _Extra ) ->
  {ok, StateName, State}.
