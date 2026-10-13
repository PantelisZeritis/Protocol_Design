mtype = { NONE, INVITE, TRYING_100, RINGING_180, OK_200, ACK, BYE, BUSY_486, DECLINE_603, NOT_FOUND_404, ABP_ACK };

// --- ΣΕΤ 1: Κανάλια από τις εφαρμογές ΠΡΟΣ το Δίκτυο (Sender -> DL) ---
chan A_to_Net_P = [2] of { mtype, bit };
chan P_to_Net_A = [2] of { mtype, bit };
chan P_to_Net_B = [2] of { mtype, bit };
chan B_to_Net_P = [2] of { mtype, bit };
chan A_to_Net_B = [2] of { mtype, bit };
chan B_to_Net_A = [2] of { mtype, bit };

// --- ΣΕΤ 2: Κανάλια από το Δίκτυο ΠΡΟΣ τις εφαρμογές (DL -> Receiver) ---
chan Net_to_P_from_A = [2] of { mtype, bit };
chan Net_to_A_from_P = [2] of { mtype, bit };
chan Net_to_B_from_P = [2] of { mtype, bit };
chan Net_to_P_from_B = [2] of { mtype, bit };
chan Net_to_B_from_A = [2] of { mtype, bit };
chan Net_to_A_from_B = [2] of { mtype, bit };

inline send_ABP(ch_out, ch_in, msg_to_send) {
    do
    :: ch_out ! msg_to_send(seq_out) ->
        if
        :: ch_in ? ABP_ACK(seq_in) ->
            if
            :: seq_in == seq_out -> 
                seq_out = 1 - seq_out; 
                break;
            :: else -> skip; 
            fi;
        :: timeout -> skip; 
        fi;
    od;
}

inline recv_ABP(ch_in, ch_out, expected_msg) {
    do
    :: ch_in ? msg_in(seq_in) ->
        ch_out ! ABP_ACK(seq_in); 
        if
        :: msg_in == expected_msg -> 
            break;
        :: else -> skip; 
        fi;
    od;
}

proctype Network() {
    mtype msg;
    bit seq;

    end:
    do
    // --- 1. Διαδρομές Alice <-> Proxy ---
    :: A_to_Net_P ? msg(seq) ->
        if
        :: Net_to_P_from_A ! msg(seq);
        :: (msg != ABP_ACK) -> skip; 
        fi;
    :: P_to_Net_A ? msg(seq) ->
        if
        :: Net_to_A_from_P ! msg(seq);
        :: (msg != ABP_ACK) -> skip;
        fi;

    // --- 2. Διαδρομές Proxy <-> Bob ---
    :: P_to_Net_B ? msg(seq) ->
        if
        :: Net_to_B_from_P ! msg(seq);
        :: (msg != ABP_ACK) -> skip;
        fi;
    :: B_to_Net_P ? msg(seq) ->
        if
        :: Net_to_P_from_B ! msg(seq);
        :: (msg != ABP_ACK) -> skip;
        fi;

    // --- 3. Διαδρομές Alice <-> Bob ---
    :: A_to_Net_B ? msg(seq) ->
        if
        :: Net_to_B_from_A ! msg(seq);
        :: (msg != ABP_ACK) -> skip;
        fi;
    :: B_to_Net_A ? msg(seq) ->
        if
        :: Net_to_A_from_B ! msg(seq);
        :: (msg != ABP_ACK) -> skip;
        fi;
    od;
}

proctype Alice() {
    bool seq_out = 0; 
    bool seq_in;      
    mtype msg_in;

    send_ABP(A_to_Net_P, Net_to_A_from_P, INVITE);
    recv_ABP(Net_to_A_from_P, A_to_Net_P, TRYING_100);
    
    do
    :: Net_to_A_from_P ? msg_in(seq_in) ->
        A_to_Net_P ! ABP_ACK(seq_in); 
        
        if
        :: msg_in == RINGING_180 -> 
            recv_ABP(Net_to_A_from_P, A_to_Net_P, OK_200); 
            
            send_ABP(A_to_Net_B, Net_to_A_from_B, ACK);
            send_ABP(A_to_Net_B, Net_to_A_from_B, BYE);
            
            recv_ABP(Net_to_A_from_B, A_to_Net_B, OK_200); 
            break; 

        :: msg_in == BUSY_486 -> break;
        :: msg_in == DECLINE_603 -> break;
        :: msg_in == NOT_FOUND_404 -> break;
        :: else -> skip; 
        fi;
    od;

    end_cleanup:
    do
    :: Net_to_A_from_P ? _(seq_in) -> A_to_Net_P ! ABP_ACK(seq_in);
    :: Net_to_A_from_B ? _(seq_in) -> A_to_Net_B ! ABP_ACK(seq_in);
    od;
}

proctype Proxy() {
    bool seq_out = 0; 
    bool seq_in;
    mtype msg_in;

    recv_ABP(Net_to_P_from_A, P_to_Net_A, INVITE);
    send_ABP(P_to_Net_A, Net_to_P_from_A, TRYING_100);
    send_ABP(P_to_Net_B, Net_to_P_from_B, INVITE);

    do
    :: Net_to_P_from_B ? msg_in(seq_in) ->
        P_to_Net_B ! ABP_ACK(seq_in); 
        
        if
        :: msg_in == RINGING_180 -> 
            send_ABP(P_to_Net_A, Net_to_P_from_A, RINGING_180); 
            recv_ABP(Net_to_P_from_B, P_to_Net_B, OK_200);
            send_ABP(P_to_Net_A, Net_to_P_from_A, OK_200);
            break;
            
        :: msg_in == BUSY_486 -> send_ABP(P_to_Net_A, Net_to_P_from_A, BUSY_486); break;
        :: msg_in == DECLINE_603 -> send_ABP(P_to_Net_A, Net_to_P_from_A, DECLINE_603); break;
        :: msg_in == NOT_FOUND_404 -> send_ABP(P_to_Net_A, Net_to_P_from_A, NOT_FOUND_404); break;
        :: else -> skip; 
        fi;
    od;

    end_cleanup:
    do
    :: Net_to_P_from_A ? _(seq_in) -> P_to_Net_A ! ABP_ACK(seq_in);
    :: Net_to_P_from_B ? _(seq_in) -> P_to_Net_B ! ABP_ACK(seq_in);
    od;
}

proctype Bob() {
    bool seq_out = 0;
    bool seq_in;
    mtype msg_in;

    recv_ABP(Net_to_B_from_P, B_to_Net_P, INVITE);

    if
    :: true -> 
       send_ABP(B_to_Net_P, Net_to_B_from_P, RINGING_180); 
       send_ABP(B_to_Net_P, Net_to_B_from_P, OK_200); 
       
       recv_ABP(Net_to_B_from_A, B_to_Net_A, ACK); 
       recv_ABP(Net_to_B_from_A, B_to_Net_A, BYE); 
       
       send_ABP(B_to_Net_A, Net_to_B_from_A, OK_200);

    :: true -> send_ABP(B_to_Net_P, Net_to_B_from_P, BUSY_486);
    :: true -> send_ABP(B_to_Net_P, Net_to_B_from_P, DECLINE_603);
    :: true -> send_ABP(B_to_Net_P, Net_to_B_from_P, NOT_FOUND_404);
    fi;

    end_cleanup:
    do
    :: Net_to_B_from_P ? _(seq_in) -> B_to_Net_P ! ABP_ACK(seq_in);
    :: Net_to_B_from_A ? _(seq_in) -> B_to_Net_A ! ABP_ACK(seq_in);
    od;
}

init {
    atomic {
        run Alice();
        run Proxy();
        run Bob();
        run Network();
    }
}