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
-record( state, { coordinator, socket, datasource, address, port, message }).
%%
%% API Functions
%%
start( Coordinator, Socket, Address, Port )->
  gen_fsm:start( ?MODULE, [ Coordinator, Socket, Address, Port ], [] ).

init([ Coordinator, Socket, Address, Port ]) ->
  { ok, Datasource } = datasource:start(),
  { ok, slot_received, #state{ coordinator=Coordinator, socket=Socket, datasource=Datasource, address=Address, port=Port }}.

slot_received({ slot, Slot }, State) ->
  % fetch message from datasource
  gen_server:cast(State#state.datasource, { get_data, self() }),
  { next_state, message_received, State }.

message_received({ message, Message }, State) ->
  % fetch next slot from coordinator
  gen_server:cast(State#state.coordinator, { nextSlot, self() }),
  { next_state, next_slot_received, State#state{ message=Message} }.

next_slot_received({ nextSlot, Slot }, State) ->
  % if slot not passed
  % deliver message, and wait for next frame
  % else ?
  Socket = State#state.socket,
  Address = State#state.address,
  Port = State#state.port,
  Message = State#state.message,
  Packet = build_packet(Message, Slot),
  gen_udp:send(Socket, Address, Port, Packet),
  { next_state, slot_received, State }.

terminate( StateName, StateData, State) ->
	gen_server:cast(State#state.datasource, stop),
	gen_udp:close(State#state.socket),
	ok.
handle_event(stop, StateName, State) ->
  utility:log("Sender wird ausgeschaltet"),
  {stop, normal, State};

%%
%% non API Functions
%%
build_packet(Message, Slot) ->
  Timestamp = timestamp(),
  Data = list_to_binary(Message)
  % Bit Syntax Expressions (Value:Size/TypeSpecifierList) http://www.erlang.org/doc/reference_manual/expressions.html
  << Data:24/binary,
     Slot:8/integer-big,
     Timestamp:64/integer-big>>.

timestamp() ->
  {MegaSecs, Secs, MicroSecs} = now(), % would erlang:timestamp() also work? i'm unsure
  (MegaSecs * math:pow(10,9)) * (Secs * math:pow(10,3)) * (MicroSecs div 1000).

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
