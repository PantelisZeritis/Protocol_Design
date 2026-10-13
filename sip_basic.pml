// Ορισμός όλων των πιθανών μηνυμάτων (ομαλής λειτουργίας και λαθών)
mtype = { INVITE, TRYING_100, RINGING_180, OK_200, ACK, BYE, BUSY_486, DECLINE_603, NOT_FOUND_404 };

// Ορισμός των καναλιών επικοινωνίας με χωρητικότητα 2 μηνυμάτων το καθένα
chan alice_to_proxy = [2] of { mtype };
chan proxy_to_alice = [2] of { mtype };
chan proxy_to_bob   = [2] of { mtype };
chan bob_to_proxy   = [2] of { mtype };
chan alice_to_bob   = [2] of { mtype };
chan bob_to_alice   = [2] of { mtype };

proctype Alice() {
    // Έναρξη κλήσης
    alice_to_proxy ! INVITE;
    proxy_to_alice ? TRYING_100;
    
    // Αναμονή για την απάντηση (ομαλή ή λάθος)
    if
    :: proxy_to_alice ? RINGING_180 -> 
        proxy_to_alice ? OK_200;
        alice_to_bob ! ACK;
        alice_to_bob ! BYE;
        bob_to_alice ? OK_200;
        printf("Alice: Call completed successfully.\n");
        
    :: proxy_to_alice ? BUSY_486 -> 
        printf("Alice: Call failed - Bob is busy (486).\n");
        
    :: proxy_to_alice ? DECLINE_603 -> 
        printf("Alice: Call failed - Bob declined (603).\n");
        
    :: proxy_to_alice ? NOT_FOUND_404 -> 
        printf("Alice: Call failed - Bob not found (404).\n");
    fi;
}

proctype Proxy() {
    // Λήψη αιτήματος και προώθηση
    alice_to_proxy ? INVITE;
    proxy_to_alice ! TRYING_100;
    proxy_to_bob ! INVITE;
    
    // Έλεγχος απάντησης του Bob και προώθηση στην Alice
    if
    :: bob_to_proxy ? RINGING_180 -> 
        proxy_to_alice ! RINGING_180;
        bob_to_proxy ? OK_200;
        proxy_to_alice ! OK_200;
        
    :: bob_to_proxy ? BUSY_486 -> 
        proxy_to_alice ! BUSY_486;
        
    :: bob_to_proxy ? DECLINE_603 -> 
        proxy_to_alice ! DECLINE_603;
        
    :: bob_to_proxy ? NOT_FOUND_404 -> 
        proxy_to_alice ! NOT_FOUND_404;
    fi;
}

proctype Bob() {
    // Λήψη του αρχικού αιτήματος
    proxy_to_bob ? INVITE;
    
    if
    :: bob_to_proxy ! RINGING_180 -> 
       // Ομαλή εκτέλεση
       bob_to_proxy ! OK_200; 
       alice_to_bob ? ACK; 
       alice_to_bob ? BYE; 
       bob_to_alice ! OK_200;
       
    :: bob_to_proxy ! BUSY_486;    
    :: bob_to_proxy ! DECLINE_603; 
    :: bob_to_proxy ! NOT_FOUND_404; 
    fi;
}

init {
    atomic {
        run Alice();
        run Proxy();
        run Bob();
    }
}