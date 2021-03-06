-module(sender).
-author("Ben Rexin <benjamin.rexin@haw-hamburg.de>").

-define(SLOTS_PER_FRAME, 20).
-define(SLOT_LENGTH, 1000/?SLOTS_PER_FRAME).

%%
%% Include files
%%
-import(util, [timestamp/0, time_till_slot/1]).
%%
%% Exported Functions
%%
%% gen_fsm requires explicit export of his required functions
-export([init/1, handle_sync_event/4, handle_info/3, code_change/4, terminate/3, handle_event/3, deliver/2]).
-compile([export_all]).
-behaviour(gen_fsm).
-record( state, { coordinator, socket, datasource, address, port, message, slot=0, next_slot=0, station}).
%%
%% API Functions
%%
start( Coordinator, Socket, Address, Port, Station )->
  %log("Starter: gestartet"),
  gen_fsm:start( ?MODULE, [ Coordinator, Socket, Address, Port, Station ], [] ).

init([ Coordinator, Socket, Address, Port, Station ]) ->
  %log("Sender: init"),
  { ok, Datasource } = datasource:start(),
  { ok, slot_received, #state{ coordinator=Coordinator, socket=Socket, datasource=Datasource, address=Address, port=Port, station=Station }}.

% fetch message from datasource
slot_received({ slot, Slot }, State) ->
  %log("[~p]Slot received: [~p]",[State#state.station, Slot]),
  gen_server:cast( State#state.datasource, { get_next_value, self() }),
  %log("[~p]Nach get_next_value",[State#state.station]),
  { next_state, message_received, State#state{ slot=Slot } };
slot_received(Unknown, State) ->
  %log("[[~p]UNKNOWN] slot_received received message [~p]",[State#state.station,Unknown]),
  { next_state, slot_received, State}.

message_received({ message, Message }, State) ->
  gen_server:cast(State#state.coordinator, next_slot),
  { next_state, next_slot_received, State#state{message=Message}};
  %log("[~p]message received",[State#state.station]),
  %log("[[~p]received Message [~p]", [State#state.station,Message]),
  
message_received(Unknown, State) ->
  %log("[[~p]UNKNOWN] message_received received message [~p]",[State#state.station,Unknown]),
  { next_state, message_received, State}.

next_slot_received({next_slot, NextSlot}, State) ->
  TimeLeft = time_till_slot(State#state.slot)+20,
  case TimeLeft > 0 of
    true ->
%      timer:sleep(TimeLeft),
      gen_fsm:send_event_after(TimeLeft, deliver),
      { next_state, deliver, State#state{next_slot=NextSlot} };
    false ->
      %log("[~p]TimeLeft<=0",[State#state.station]),
      { next_state, slot_received, State#state{next_slot=NextSlot} }
  end.

deliver(deliver, State) ->
      Socket = State#state.socket,
      Address = State#state.address,
      Port = State#state.port,
      Message = State#state.message,
      Packet = build_packet(Message, State#state.next_slot),
      gen_udp:send(Socket, Address, Port, Packet),
      %log("[~p]Nachricht gesendet",[State#state.station]),
      { next_state, slot_received, State }.

handle_event(stop, _StateName, State) ->
  utility:log("[~p]Sender wird ausgeschaltet",[State#state.station]),
  {stop, normal, State}.

terminate( _StateName, _StateData, State) ->
	%log("[~p]TERMINATING!",[State#state.station]),
	gen_server:cast(State#state.datasource, stop),
	gen_udp:close(State#state.socket),
	ok.

%%
%% non API Functions
%%

% Bit Syntax Expressions (Value:Size/TypeSpecifierList) http://www.erlang.org/doc/reference_manual/expressions.html
build_packet( Message, Slot ) ->
  %log("build packet"),
  Timestamp = timestamp(),
  %log("Timestamp [~p]", [Timestamp]),
  %log("Message [~p]", [Message]),
  Data = list_to_binary(Message),
  % Bit Syntax Expressions (Value:Size/TypeSpecifierList) http://www.erlang.org/doc/reference_manual/expressions.html
  Packet = << Data:24/binary,Slot:8/integer-big,Timestamp:64/integer-big>>,
  %log("Packet [~p]",[Packet]),
  Packet.

log(Message) ->
	util:log( "Sender.log", Message ).
log(Message, Data) ->
	util:log( "Sender.log", Message, Data ).

%% gen_fsm API requirements
state_name( _Event, _From, State ) ->
  {reply, ok, state_name, State}.

handle_sync_event( _Event, _From, StateName, State ) ->
  {reply, ok, StateName, State}.

handle_info( Info, StateName, State ) ->
  %log("Info: [~p]",[Info]),
  {noreply, StateName, State}.

code_change( _OldVsn, StateName, State, _Extra ) ->
  {ok, StateName, State}.
