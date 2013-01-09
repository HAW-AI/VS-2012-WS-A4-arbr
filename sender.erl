-module(sender).
-author("Ben Rexin <benjamin.rexin@haw-hamburg.de>").

-define(SLOTS_PER_FRAME, 20).
-define(SLOT_LENGTH, 1000/?SLOTS_PER_FRAME).

%%
%% Include files
%%
-import(util, [log/2, timestamp/0, time_till_slot/1]).
%%
%% Exported Functions
%%
%% gen_fsm requires explicit export of his required functions
-export([init/1, handle_sync_event/4, handle_info/3, code_change/4, terminate/3, handle_event/3]).

-behaviour(gen_fsm).
-record( state, { coordinator, socket, datasource, address, port, message, slot }).
%%
%% API Functions
%%
start( Coordinator, Socket, Address, Port )->
  gen_fsm:start( ?MODULE, [ Coordinator, Socket, Address, Port ], [] ).

init([ Coordinator, Socket, Address, Port ]) ->
  { ok, Datasource } = datasource:start(),
  { ok, slot_received, #state{ coordinator=Coordinator, socket=Socket, datasource=Datasource, address=Address, port=Port }}.

% fetch message from datasource
slot_received({ slot, Slot }, State) ->
  gen_server:cast( State#state.datasource, { get_data, self() }),
  { next_state, message_received, State#state{ slot=Slot } }.

message_received({ message, Message }, State) ->
  % fetch next slot from coordinator
  gen_server:cast(State#state.coordinator, { nextSlot, self() }),
  { next_state, next_slot_received, State#state{ message=Message} }.

next_slot_received({ nextSlot, Slot }, State) ->
  % if slot not passed
  % deliver message, and wait for next frame
  % else ?
  case time_till_slot(State#state.slot) > 0 of
    true ->
      Socket = State#state.socket,
      Address = State#state.address,
      Port = State#state.port,
      Message = State#state.message,
      Packet = build_packet(Message, Slot),
      gen_udp:send(Socket, Address, Port, Packet);
    false ->
      ok % missed slot, should not send to prevent collision. Drop message?
  end,
  { next_state, slot_received, State }.

terminate( _StateName, _StateData, State) ->
	gen_server:cast(State#state.datasource, stop),
	gen_udp:close(State#state.socket),
	ok.

handle_event(stop, _StateName, State) ->
  utility:log("Sender wird ausgeschaltet"),
  {stop, normal, State}.

%%
%% non API Functions
%%

% Bit Syntax Expressions (Value:Size/TypeSpecifierList) http://www.erlang.org/doc/reference_manual/expressions.html
build_packet( Message, Slot ) ->
  Timestamp = timestamp().

log(Message) ->
	util:log( "Sender.log", Message ).

%% gen_fsm API requirements
state_name( _Event, _From, State ) ->
  {reply, ok, state_name, State}.

handle_sync_event( _Event, _From, StateName, State ) ->
  {reply, ok, StateName, State}.

handle_info( _Info, StateName, State ) ->
  {noreply, StateName, State}.

code_change( _OldVsn, StateName, State, _Extra ) ->
  {ok, StateName, State}.
