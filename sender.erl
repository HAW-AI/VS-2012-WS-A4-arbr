-module(sender).
-author("Ben Rexin <benjamin.rexin@haw-hamburg.de>").

%%
%% Include files
%%
-import(util, [log/2]).
%%
%% Exported Functions
%%
%% gen_fsm requires explicit export of his required functions
-export([init/1, handle_sync_event/4, handle_info/3, code_change/4, terminate/3]).

-behaviour(gen_fsm).
-record( state, { coordinator, socket, datasource }).
%%
%% API Functions
%%
start(Coordinator,Socket)->
  gen_fsm:start( ?MODULE, [ Coordinator, Socket ], [] ).

init([ Coordinator, Socket ]) ->
  { ok, Datasource } = datasource:start(),
  { ok, get_data, #state{coordinator = Coordinator, socket=Socket, datasource=Datasource }}.

slot_received({ slot, Slot }, State) ->
  % fetch message from datasource
  gen_server:cast(State#state.datasource, { get_data, self() }),
  { next_state, message_received, State }.

message_received({ message, Message }, State) ->
  % fetch next slot from coordinator
  gen_server:cast(State#state.coordinator, { nextSlot, self() }),
  { next_state, next_slot_received, State }.

next_slot_received({ nextSlot, Slot }, State) ->
  % deliver message, and wait for next frame

  %gen_udp:send(Socket, Address, Port, Packet)

  ok.

terminate( StateName, StateData, State) ->
	gen_server:cast(State#state.datasource, stop),
	gen_udp:close(State#state.socket),
	ok.

get_data({ slot, Slot }, State) ->
	gen_server:cast(State#state.datasource, {get_data,self()}).

%%
%% non API Functions
%%
log(Message) ->
	util:log( "Datasource.log", Message ).

%% gen_fsm API requirements
state_name( _Event, _From, State ) ->
  {reply, ok, state_name, State}.

handle_sync_event( _Event, _From, StateName, State ) ->
  {reply, ok, StateName, State}.

handle_info( _Info, StateName, State ) ->
  {noreply, StateName, State}.

code_change( _OldVsn, StateName, State, _Extra ) ->
  {ok, StateName, State}.
