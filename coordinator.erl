-module(coordinator).
-author("Ben Rexin <benjamin.rexin@haw-hamburg.de>").
-compile([export_all]).

-behaviour(gen_server).
% tasks
% - start datasource
% - start receiver
% - start sender
% - manage slots

-export([init/1, handle_cast/2, handle_info/2, code_change/3, terminate/2, handle_call/3]).

-define(SENDPORT,14010).

-record(state, {receiverPID, senderPID, sendport, recport, wished_slots=dict:new(), used_slots=dict:new(), next_slot }).

start([RecPort,Station,MulticastIP,LocalIP])->
	log("Coordinator gestartet"),
	gen_server:start(?MODULE,[RecPort,?SENDPORT,Station,MulticastIP,LocalIP],[]).

init([StringRecPort,SendPort,Station,StringMulticastIP,StringLocalIP])->
	log("Coordinator init [~p]",[Station]),
	%http://erldocs.com/R15B/kernel/gen_udp.html
	%http://erldocs.com/R15B/kernel/inet.html#setopts/2
	%http://stackoverflow.com/questions/78826/erlang-multicast
	
	RecPort = list_to_integer(atom_to_list(StringRecPort)),
	{ ok, MulticastIP } = inet_parse:address(atom_to_list(StringMulticastIP)),
	{ ok, LocalIP } = inet_parse:address(atom_to_list(StringLocalIP)),
	log("Coordinator IPs angepasst"),
	log("RecPort: ~p",[RecPort]),
	log("MulticastIP: ~p",[MulticastIP]),
	log("LocalIP: ~p",[LocalIP]),
	{ok,RecSocket} = gen_udp:open(RecPort,[
										   binary,
										   inet, 
										   {active, true},
										   {reuseaddr, true},
										   {multicast_loop, true},
										   {add_membership,{MulticastIP,LocalIP}},
										   {multicast_if, LocalIP}]
								 ),
	log("Coordinator RecSocket geöffnet"),
	{ok,SendSocket} = gen_udp:open(SendPort,[
											 binary, 
											 inet,
											 {active, true},
											 {reuseaddr, true},
											 {multicast_loop, true},
											 {multicast_if, LocalIP},
											 {ip,LocalIP}]
								  ),
	log("Coordinator Sockets geöffnet"),

	{ok,ReceiverPID} = receiver:start(self(),RecSocket),
	log("Coordinator: Receiver gestartet"),
	{ok,SenderPID} = sender:start(self(),SendSocket,MulticastIP,RecPort),

	gen_udp:controlling_process(RecSocket, ReceiverPID),
	gen_udp:controlling_process(SendSocket, SenderPID),
	
	log("Coordinator - alle Sockets geöffnet, und sender/receiver gestartet"),
	next_frame_timer(),
	random:seed(now()),
	NextSlot = random:uniform(20) -1,

	{ok, #state{
				receiverPID=ReceiverPID,
				senderPID=SenderPID,
				sendport=SendPort,
				recport=RecPort,
				next_slot=NextSlot
				}}.

next_frame_timer() ->
	log("Next frame timer"),
	log("Timestamp: [~p]",[util:timestamp()]),
	log("Millisec: [~p]",[(util:timestamp() rem 1000)]),
	log("Timediff: [~p]",[1000 - (util:timestamp() rem 1000)]),
	erlang:send_after(1000 - (util:timestamp() rem 1000), self(), frame_start).

handle_cast(frame_start, State) ->
	log("Coordinator: start frame"),
	% send all non collided messages to sink (ugly hack!)
	CollisionFreeMessages = dict:filter(fun(_Key, Value) -> length(Value) == 1 end, State#state.used_slots),
	dict:fold(fun(_Key, Value, _Accu) -> gen_server:cast(self(),{ datasink, Value }) end, ok, CollisionFreeMessages),
	% send wished or free slot to sender
	Slot = calculate_next_slot(State),
	log("Sending nextslot"),
	gen_fsm:send_event(State#state.senderPID, { slot, Slot }),
	next_frame_timer(),
	{noreply, State#state{ used_slots=dict:new(), wished_slots=dict:new(), next_slot=Slot }};

handle_cast({datasink, Data},State)->
	log("Neue Nachricht empfangen: ~p",[Data]),
	{noreply, State};

handle_cast({nextSlot, SenderPID}, State)->
	log("Der Sender hat nach dem n�chsten Slot gefragt"),
	NextSlot = calculate_next_slot(State),
	log("Next Slot: [~p]",[NextSlot]),
	gen_fsm:send_event(SenderPID, { nextSlot, NextSlot }),
	{noreply, State#state{ next_slot=NextSlot }};

handle_cast({recieved, _RecievedTimestamp, Packet}, State)->
	log("Coordinator recieved"),
	{ Station, StationNumber, Data, SlotWish, Timestamp} = parse_packet(Packet),
	Slot = util:slot_from(Timestamp), % or from RecievedTimestamp?

	case slot_collision(Slot, State#state.used_slots) of
		true ->
			log("Collision!"); % by dict:fetch(Slot, State#state.used_slots)
		false -> 
			ok
	end,
	UsedSlots = dict:append(Slot, { Station, StationNumber, Data }, State#state.used_slots),
	WishedSlots = dict:append(SlotWish, StationNumber, State#state.wished_slots),
	{noreply, State#state{ used_slots=UsedSlots, wished_slots=WishedSlots }}.

calculate_next_slot(State) ->
	log("NextSlot [~p] NextSlotTaken? [~p]",[State#state.next_slot, dict:is_key(State#state.next_slot, State#state.wished_slots)]),
	Count = case dict:is_key(State#state.next_slot, State#state.wished_slots) of
		true ->
			log("Wished Slots by Stations [~p]", [dict:fetch(State#state.next_slot, State#state.wished_slots)]),
			length(dict:fetch(State#state.next_slot, State#state.wished_slots));
		false ->
			0 % trigger random
	end,
	CalculatedSlot = if
		Count < 2 ->
			State#state.next_slot;
		true ->
			CollisionFreeUsedSlots = dict:filter(fun(_Key, Value) -> length(Value) == 1 end, State#state.wished_slots),
			UsedSlots = dict:fetch_keys(CollisionFreeUsedSlots),
			FreeSlots = werkzeug:shuffle(lists:subtract(lists:seq(0,19), UsedSlots)),
			log("used slots [~p]",[UsedSlots]),
			log("free slots [~p]",[FreeSlots]),
			if 
				length(FreeSlots) == 0 -> 
					0; % ugly fallback, no free slot found!
				true -> 
					[ TempSlot | _ ] = FreeSlots,
					TempSlot
			end
	end,
	log("CalculatedSlot [~p]",[CalculatedSlot]),
	CalculatedSlot.

slot_collision(Slot, UsedSlots) ->
	dict:is_key(Slot, UsedSlots).

parse_packet(Packet) ->
	<<Station:8/binary,
    StationNumber:2/binary,
    Data:14/binary,
    Slot:8/integer-big,
    Timestamp:64/integer-big
  >> = Packet,
  {Station, StationNumber, Data, Slot, Timestamp }.

terminate(normal,State)->
	log("TERMINATING!"),
	gen_server:cast(State#state.receiverPID,{stop}),
	gen_fsm:cast(State#state.senderPID,{stop}),
	ok.

log(Message) ->
	util:log("Coordinator.log",Message).
log(Message, Data) ->
	util:log("Coordinator.log",Message, Data).

%% durch gen_server vorgegeben
handle_call(_Request, _From, State) ->
  {reply, ok, State}.

handle_info(frame_start, State) ->
  log("Got frame_start"),
  gen_server:cast(self(), frame_start),
  {noreply, State};

handle_info(_Info, State) ->
  {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.
