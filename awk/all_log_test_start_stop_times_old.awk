BEGIN {
    OFS = ","
    print "start_date_time", "test_id", "monitor", "report_window", "record_id", "end_date_time", "total_test_time", "total-sec", "dom-sec", "render-sec", "doc-complete-sec", "title-sec", "fps", "fcp", "fp", "tti", "vct", "lcp", "cls", "wire-sec", "client-sec", "act-rt", "exp-rt" > "hawk_test_start_end.csv"
    print "start_date_time", "end_date_time", "total_test_time", "test_type", "test_id", "report_window", "test_record_id" > "testeng_test_times.csv"
    print "Timestamp,Agent Service Status,CommEng Status,Total Memory (KB),Used Memory (KB),Available Memory (KB),Free Memory Percentage,CommEng PID,TxEng PID,TestEng PID" > "sns_defib_analysis.csv"
    print "request_time", "test_id", "test_type", "test_record_id" > "commeng_test_time.csv"

    # Initialize variables
    timestamp = agent_status = commeng_status = ""
    total_mem = used_mem = available_mem = ""
    free_mem_pct = commeng_pid = txeng_pid = ""
    testeng_pid = ""
}

/<SimpleHttpsForwarder> Calling BuildOriginalRequestResponse/ {
    filename = FILENAME;
    block = $0;
    while (getline > 0) {
        block = block "\n" $0;
        if ($0 ~ /\}\]\]/) break;  # End of CPTID JSON block
    }

    # Extract timestamp (format: 2025-05-15 14:33:12.962)
    if (match(block, /^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}/, ts)) {
        request_time = ts[0];               # Human-readable format for CSV
        clean_time = request_time;
        gsub(/[^0-9]/, "", clean_time);     # For test_record_id
    } else {
        next;
    }

    # Extract CPTID JSON block
    if (match(block, /CPTID: *\[((.|\n)*?)\]/, arr)) {
        cptid_block = arr[1];

        while (match(cptid_block, /\{"t":([0-9]+),"s":([0-9]+)\}/, parts)) {
            test_id = parts[1];
            test_type = parts[2];
            test_record_id = clean_time test_id;

            print request_time, test_id, test_type, test_record_id, filename
            print request_time, test_id, test_type, test_record_id >> "commeng_test_time.csv";

            cptid_block = substr(cptid_block, RSTART + RLENGTH);
        }
    }
}

/TEST-START/ {
    filename = FILENAME;
    log_time = $1 " " $2  # Capture log timestamp
    test_id = ""
    monitor = ""
    report_window = ""

    for (i = 4; i <= NF; i++) {
        if ($i ~ /^id=/) {
            test_id = $i
            gsub("id=", "", test_id)
            sub(/^[SI]/, "", test_id)
            gsub(/,/, "", test_id)
            
            if ((i+1) <= NF) {
                monitor = $(i+1)
                gsub(/,/, "", monitor)
            }
        } else if ($i ~ /^rpt-window=/) {
            report_window = $(i+1)
            gsub(/rpt-window=|,/, "", $i)
            report_window = $i " " report_window
            gsub(/,/, "", report_window)
            i++
        }
    }
    
    record_id = report_window test_id
    gsub(/[\/: ]/, "", record_id)
    
    data[record_id] = log_time "," test_id "," monitor "," report_window "," record_id
}

/TEST-END/ {
    filename = FILENAME;
    end_date_time = $1 " " $2  # Capture log timestamp
    test_id = ""
    monitor = ""
    report_window = ""
    total_sec = dom_sec = render_sec = doc_complete_sec = title_sec = fps = ""
    fcp = fp = tti = vct = lcp = cls = wire_sec = client_sec = act_rt = exp_rt = ""
    
    for (i = 4; i <= NF; i++) {
        if ($i ~ /^id=/) {
            test_id = $i
            gsub("id=", "", test_id)
            sub(/^[SI]/, "", test_id)
            gsub(/,/, "", test_id)
        } else if ($i ~ /^rpt-window=/) {
            report_window = $(i+1)
            gsub(/rpt-window=|,/, "", $i)
            report_window = $i " " report_window
            gsub(/,/, "", report_window)
            i++
        } else if ($i ~ /-sec=/ || $i ~ /^fps=/ || $i ~ /^fcp=/ || $i ~ /^fp=/ || $i ~ /^tti=/ || $i ~ /^vct=/ || $i ~ /^lcp=/ || $i ~ /^cls=/ || $i ~ /^wire-sec=/ || $i ~ /^client-sec=/ || $i ~ /^act-rt=/ || $i ~ /^exp-rt=/) {
            split($i, kv, "=")
            metric = kv[1]
            value = kv[2]
            gsub(/,/, "", value)

            if (metric == "total-sec") total_sec = value
            else if (metric == "dom-sec") dom_sec = value
            else if (metric == "render-sec") render_sec = value
            else if (metric == "doc-complete-sec") doc_complete_sec = value
            else if (metric == "title-sec") title_sec = value
            else if (metric == "fps") fps = value
            else if (metric == "fcp") fcp = value
            else if (metric == "fp") fp = value
            else if (metric == "tti") tti = value
            else if (metric == "vct") vct = value
            else if (metric == "lcp") lcp = value
            else if (metric == "cls") cls = value
            else if (metric == "wire-sec") wire_sec = value
            else if (metric == "client-sec") client_sec = value
            else if (metric == "act-rt") act_rt = value
            else if (metric == "exp-rt") exp_rt = value
        }
    }
    
    record_id = report_window test_id
    gsub(/[\/: ]/, "", record_id)
    
    if (record_id in data) {
        split(data[record_id], fields, ",")
        start_date_time = fields[1]
        
        # Convert timestamps to epoch milliseconds
        cmd = "date -d '" start_date_time "' +%s.%3N"
        cmd | getline start_epoch
        close(cmd)
        
        cmd = "date -d '" end_date_time "' +%s.%3N"
        cmd | getline end_epoch
        close(cmd)
        
        total_test_time = sprintf("%.3f", end_epoch - start_epoch)
        print data[record_id]"," end_date_time"," total_test_time "," total_sec "," dom_sec "," render_sec "," doc_complete_sec "," title_sec "," fps "," fcp "," fp "," tti "," vct "," lcp "," cls "," wire_sec "," client_sec "," act_rt "," exp_rt "," filename
        print data[record_id], end_date_time, total_test_time, total_sec, dom_sec, render_sec, doc_complete_sec, title_sec, fps, fcp, fp, tti, vct, lcp, cls, wire_sec, client_sec, act_rt, exp_rt >> "hawk_test_start_end.csv"
        delete data[record_id]  # Remove processed entry
    }
}

/TestExecutionBegin/ {
    filename = FILENAME;
    split($2, tempData, ",");
    min_time = tempData[1];
    date_time = substr($1, index($1, ".") + 1);
    start_date_time = date_time" "min_time;
    testID = $7;
    gsub(/[^0-9]/, "", testID);
    monitorSet = $8;
    monitorSet = gensub(/[^0-9]*/, "", "g", monitorSet);

    match($0, /\[testReportWindowTime, ([0-9\/: ]+[APMapm]+)\]/, arr);
    if (arr[1] != "") {
        actualRuntime = arr[1];
    } else {
        actualRuntime = "";
    }

    gsub(/AM|am/, "AM", actualRuntime);
    gsub(/PM|pm/, "PM", actualRuntime);
    split(actualRuntime, datetime, " ");
    date = datetime[1];
    time = datetime[2];
    split(time, time_parts, ":");
    hour = time_parts[1];
    minute = time_parts[2];
    am_pm = tolower(datetime[3]);

    if (am_pm == "pm" && hour != 12) {
        hour += 12;
    }
    if (am_pm == "am" && hour == 12) {
        hour = "00";
    }
    converted_time = sprintf("%02d:%02d:%02d", hour, minute, time_parts[3]);

    formattedRuntime = date " " converted_time;
    record_id = formattedRuntime "" testID;
    gsub(/[^0-9]/, "", record_id);

    data[record_id] = start_date_time "," testID "," monitorSet "," formattedRuntime "," record_id;
}

/TestExecutionEnd/ {
    filename = FILENAME;
    split($2, tempData, ",");
    min_time = tempData[1];
    date_time = substr($1, index($1, ".") + 1);
    end_date_time = date_time" "min_time
    testID = $7;
    gsub(/[^0-9]/, "", testID);
    monitorSet = $8;
    monitorSet = gensub(/[^0-9]*/, "", "g", monitorSet);
    match($0, /\[testReportWindowTime, ([0-9\/: ]+[APMapm]+)\]/, arr);
    if (arr[1] != "") {
        actualRuntime = arr[1];
    } else {
        actualRuntime = "";
    }
    gsub(/AM|am/, "AM", actualRuntime);
    gsub(/PM|pm/, "PM", actualRuntime);
    split(actualRuntime, datetime, " ");
    date = datetime[1];
    time = datetime[2];
    
    split(time, time_parts, ":");
    hour = time_parts[1];
    minute = time_parts[2];
    am_pm = tolower(datetime[3]);
    if (am_pm == "pm" && hour != 12) {
        hour += 12;
    }
    if (am_pm == "am" && hour == 12) {
        hour = "00";
    }
    converted_time = sprintf("%02d:%02d:%02d", hour, minute, time_parts[3]);

    formattedRuntime = date " " converted_time;
    record_id = formattedRuntime "" testID;
    gsub(/[^0-9]/, "", record_id);

    if (record_id in data) {
        split(data[record_id], fields, ",")
        start_date_time = fields[1]
        cmd = "date -d '" start_date_time "' +%s.%3N"
        cmd | getline start_epoch
        close(cmd)
        
        cmd = "date -d '" end_date_time "' +%s.%3N"
        cmd | getline end_epoch
        close(cmd)
        
        total_test_time = sprintf("%.3f", end_epoch - start_epoch)
        print start_date_time "," end_date_time "," total_test_time "," testID "," monitorSet "," formattedRuntime "," record_id "," filename
        print start_date_time, end_date_time, total_test_time, testID, monitorSet, formattedRuntime, record_id >> "testeng_test_times.csv"
        delete data[record_id]  # Remove processed entry
    }
    
}

# To analyze the sns_defib_logs
/^[0-9]{2}\/[0-9]{2}\/[0-9]{4}/ {
    timestamp = $1 " " $2
    in_block = 1
    agent_status = commeng_status = ""
    total_mem = used_mem = available_mem = ""
    free_mem_pct = commeng_pid = txeng_pid = testeng_pid = ""
}

/^Checking for Agent service hang/ {
    getline
    agent_status = $1
}

/^Checking for sustained Harmony CommEng not running/ {
    getline
    commeng_status = $1
}

/^Mem:/ {
    total_mem = $2
    used_mem = $3
    available_mem = $7
}

/CommEng\.dll/ { commeng_pid = $2 }
/TxEng\.dll/   { txeng_pid = $2 }
/TestEng\.dll/ { testeng_pid = $2 }

/^Free Memory percentage:/ {
    if (in_block) {
        free_mem_pct = int($4 * 100)
        print timestamp "," agent_status "," commeng_status "," total_mem "," used_mem "," available_mem "," free_mem_pct "," commeng_pid "," txeng_pid "," testeng_pid "," filename >> "sns_defib_analysis.csv"
        in_block = 0  # reset for next block
    }
}
