mtype = { NONE, INVITE, TRYING_100, RINGING_180, OK_200, ACK, BYE, BUSY_486, DECLINE_603, NOT_FOUND_404 };

// --- Εσωτερικά Κανάλια (SIP <-> myTCP) ---
chan sip_alice_to_tcp = [2] of { mtype }; 
chan tcp_to_sip_alice = [2] of { mtype }; 

chan sip_proxy_to_tcp = [2] of { mtype };
chan tcp_to_sip_proxy = [2] of { mtype };

chan sip_bob_to_tcp   = [2] of { mtype };
chan tcp_to_sip_bob   = [2] of { mtype };

// --- Εξωτερικά Κανάλια (myTCP <-> Network) ---
chan net_A_to_P = [2] of { mtype }; 
chan net_P_to_A = [2] of { mtype }; 
chan net_P_to_B = [2] of { mtype }; 
chan net_B_to_P = [2] of { mtype }; 
chan net_A_to_B = [2] of { mtype };
chan net_B_to_A = [2] of { mtype };


proctype Alice() {
    sip_alice_to_tcp ! INVITE;
    tcp_to_sip_alice ? TRYING_100;
    
    if
    :: tcp_to_sip_alice ? RINGING_180 -> 
        tcp_to_sip_alice ? OK_200;
        sip_alice_to_tcp ! ACK;
        sip_alice_to_tcp ! BYE;
        tcp_to_sip_alice ? OK_200;
    :: tcp_to_sip_alice ? BUSY_486;
    :: tcp_to_sip_alice ? DECLINE_603;
    :: tcp_to_sip_alice ? NOT_FOUND_404;
    fi;
}

proctype Proxy() {
    tcp_to_sip_proxy ? INVITE;
    sip_proxy_to_tcp ! TRYING_100;
    sip_proxy_to_tcp ! INVITE;
    
    if
    :: tcp_to_sip_proxy ? RINGING_180 -> 
        sip_proxy_to_tcp ! RINGING_180;
        tcp_to_sip_proxy ? OK_200;
        sip_proxy_to_tcp ! OK_200;
    :: tcp_to_sip_proxy ? BUSY_486 -> sip_proxy_to_tcp ! BUSY_486;
    :: tcp_to_sip_proxy ? DECLINE_603 -> sip_proxy_to_tcp ! DECLINE_603;
    :: tcp_to_sip_proxy ? NOT_FOUND_404 -> sip_proxy_to_tcp ! NOT_FOUND_404;
    fi;
}

proctype Bob() {
    tcp_to_sip_bob ? INVITE;
    
    if
    :: sip_bob_to_tcp ! RINGING_180 -> 
       sip_bob_to_tcp ! OK_200; 
       tcp_to_sip_bob ? ACK; 
       tcp_to_sip_bob ? BYE; 
       sip_bob_to_tcp ! OK_200;
    :: sip_bob_to_tcp ! BUSY_486;
    :: sip_bob_to_tcp ! DECLINE_603;
    :: sip_bob_to_tcp ! NOT_FOUND_404;
    fi;
}


proctype myTCP_Alice() {
    mtype msg_in;
    mtype pending_msg = NONE;
    byte retries = 0;

    do
    :: sip_alice_to_tcp ? msg_in ->
        if
        :: (msg_in == INVITE || msg_in == BYE) -> pending_msg = msg_in; retries = 0;
        :: else -> pending_msg = NONE; 
        fi;

        if
        :: (msg_in == INVITE) -> net_A_to_P ! msg_in;
        :: (msg_in == ACK || msg_in == BYE) -> net_A_to_B ! msg_in;
        fi;

    :: net_P_to_A ? msg_in ->
        tcp_to_sip_alice ! msg_in; 
        pending_msg = NONE;           
        
    :: net_B_to_A ? msg_in ->
        tcp_to_sip_alice ! msg_in;
        pending_msg = NONE;

    :: timeout ->
        if
        :: (pending_msg != NONE && retries < 3) ->
            retries++;
            if
            :: (pending_msg == INVITE) -> net_A_to_P ! pending_msg;
            :: (pending_msg == BYE) -> net_A_to_B ! pending_msg;
            fi;
        :: (pending_msg != NONE && retries == 3) ->
            pending_msg = NONE; 
        :: else -> skip;
        fi;
    od;
}

proctype myTCP_Proxy() {
    mtype msg_in;
    mtype pending_msg = NONE;
    byte retries = 0;

    do
    :: sip_proxy_to_tcp ? msg_in ->
        if
        :: (msg_in == INVITE) ->
            pending_msg = msg_in;
            retries = 0;
            net_P_to_B ! msg_in;
        :: (msg_in != INVITE) ->
            pending_msg = NONE;
            net_P_to_A ! msg_in;
        fi;

    :: net_A_to_P ? msg_in -> tcp_to_sip_proxy ! msg_in;
        
    :: net_B_to_P ? msg_in ->
        tcp_to_sip_proxy ! msg_in; 
        pending_msg = NONE;           

    :: timeout ->
        if
        :: (pending_msg == INVITE && retries < 3) ->
            retries++;
            net_P_to_B ! pending_msg;
        :: (pending_msg == INVITE && retries == 3) ->
            pending_msg = NONE;
        :: else -> skip;
        fi;
    od;
}

proctype myTCP_Bob() {
    mtype msg_in;
    mtype pending_msg = NONE;
    byte retries = 0;
    bool call_established = false; 

    do
    :: sip_bob_to_tcp ? msg_in ->
        if
        :: (msg_in == RINGING_180 || msg_in == BUSY_486 || msg_in == DECLINE_603 || msg_in == NOT_FOUND_404) ->
            net_B_to_P ! msg_in;
            
        :: (msg_in == OK_200) ->
            if
            :: !call_established -> 
                pending_msg = OK_200;
                retries = 0;
                net_B_to_P ! msg_in;
                call_established = true;
            :: call_established -> 
                pending_msg = NONE;
                net_B_to_A ! msg_in;
            fi;
        fi;

    :: net_P_to_B ? msg_in -> tcp_to_sip_bob ! msg_in;

    :: net_A_to_B ? msg_in ->
        tcp_to_sip_bob ! msg_in;
        if
        :: (msg_in == ACK) -> pending_msg = NONE;
        :: else -> skip;
        fi;

    :: timeout ->
        if
        :: (pending_msg == OK_200 && retries < 3) ->
            retries++;
            net_B_to_P ! pending_msg;
        :: (pending_msg == OK_200 && retries == 3) ->
            pending_msg = NONE;
        :: else -> skip;
        fi;
    od;
}


proctype Network() {
    mtype msg;
    do
    :: net_A_to_P ? msg -> if :: tcp_to_sip_proxy ! msg; :: skip; fi;
    :: net_P_to_A ? msg -> if :: tcp_to_sip_alice ! msg; :: skip; fi;
    :: net_P_to_B ? msg -> if :: tcp_to_sip_bob ! msg; :: skip; fi;
    :: net_B_to_P ? msg -> if :: tcp_to_sip_proxy ! msg; :: skip; fi;
    :: net_A_to_B ? msg -> if :: tcp_to_sip_bob ! msg; :: skip; fi;
    :: net_B_to_A ? msg -> if :: tcp_to_sip_alice ! msg; :: skip; fi;
    od;
}

init {
    atomic {
        run Alice(); run Proxy(); run Bob();
        run myTCP_Alice(); run myTCP_Proxy(); run myTCP_Bob();
        run Network();
    }
}

ABP χωρις τα tcp πλεον για τα μηνυματα