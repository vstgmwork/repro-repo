BEGIN {
    OFS = ","
    print "start_date_time", "test_id", "monitor", "report_window", "record_id", "end_date_time", "total_test_time", "total-sec", "dom-sec", "render-sec", "doc-complete-sec", "title-sec", "fps", "fcp", "fp", "tti", "vct", "lcp", "cls", "wire-sec", "client-sec", "act-rt", "exp-rt" > "hawk_test_start_end.csv"
    print "start_date_time", "end_date_time", "total_test_time", "test_id", "monitor_type", "report_window", "test_record_id" > "testeng_test_times.csv"
    print "Timestamp,Agent Service Status,CommEng Status,Total Memory (KB),Used Memory (KB),Available Memory (KB),Free Memory Percentage,CommEng PID,TxEng PID,TestEng PID" > "sns_defib_analysis.csv"
    print "date_time", "test_id", "test_type", "report_time" > "commeng_test_time.csv"
}

/<SimpleHttpsForwarder> Calling BuildOriginalRequestResponse/ {
    if (match($0, /^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}/, ts_arr)) {
        ts = ts_arr[0]
        if (match($0, /CPTID: \[([^]]+)\]/, arr)) {
            cptid_data = arr[1]
            gsub(/[\\{}]/, "", cptid_data)
            gsub(/"t":|,"s":/, ",", cptid_data)
            sub(/^,/, "", cptid_data)
            lines = split(cptid_data, data, ",")
            for (i = 1; i <= lines; i += 3) {
                report_time = ts data[i]
                gsub(/[^0-9]/, "", report_time)
                print ts "," data[i] "," data[i+1] "," report_time >> "commeng_test_time.csv"
            }
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
        # print data[record_id]"," end_date_time"," total_test_time "," total_sec "," dom_sec "," render_sec "," doc_complete_sec "," title_sec "," fps "," fcp "," fp "," tti "," vct "," lcp "," cls "," wire_sec "," client_sec "," act_rt "," exp_rt "," filename
        print data[record_id], end_date_time, total_test_time, total_sec, dom_sec, render_sec, doc_complete_sec, title_sec, fps, fcp, fp, tti, vct, lcp, cls, wire_sec, client_sec, act_rt, exp_rt >> "hawk_test_start_end.csv"
        delete data[record_id]  # Remove processed entry
    }
}

/TestExecutionBegin/ {
    filename = FILENAME
    split($2, tempData, ",")
    min_time = tempData[1]
    date_time = substr($1, index($1, ".") + 1)
    start_date_time = date_time " " min_time
    testID = $7
    gsub(/[^0-9]/, "", testID)
    monitorSet = gensub(/[^0-9]*/, "", "g", $8)

    match($0, /\[testReportWindowTime, ([0-9\/: ]+[APMapm]+)\]/, arr)
    actualRuntime = (arr[1] != "") ? arr[1] : ""

    gsub(/(am|pm)/i, toupper(substr(actualRuntime, length(actualRuntime) - 1)), actualRuntime)
    split(actualRuntime, datetime, " ")
    split(datetime[2], time_parts, ":")

    hour = time_parts[1] + 0
    minute = time_parts[2]
    second = time_parts[3]
    am_pm = tolower(datetime[3])

    if (am_pm == "pm" && hour != 12) hour += 12
    if (am_pm == "am" && hour == 12) hour = 0
    converted_time = sprintf("%02d:%02d:%02d", hour, minute, second)
    formattedRuntime = datetime[1] " " converted_time

    record_id = formattedRuntime testID
    gsub(/[^0-9]/, "", record_id)
    data[record_id] = start_date_time "," testID "," monitorSet "," formattedRuntime "," record_id
}

/TestExecutionEnd/ {
    filename = FILENAME
    split($2, tempData, ",")
    min_time = tempData[1]
    date_time = substr($1, index($1, ".") + 1)
    end_date_time = date_time " " min_time
    testID = $7
    gsub(/[^0-9]/, "", testID)
    monitorSet = gensub(/[^0-9]*/, "", "g", $8)

    match($0, /\[testReportWindowTime, ([0-9\/: ]+[APMapm]+)\]/, arr)
    actualRuntime = (arr[1] != "") ? arr[1] : ""

    gsub(/(am|pm)/i, toupper(substr(actualRuntime, length(actualRuntime) - 1)), actualRuntime)
    split(actualRuntime, datetime, " ")
    split(datetime[2], time_parts, ":")

    hour = time_parts[1] + 0
    minute = time_parts[2]
    second = time_parts[3]
    am_pm = tolower(datetime[3])

    if (am_pm == "pm" && hour != 12) hour += 12
    if (am_pm == "am" && hour == 12) hour = 0
    converted_time = sprintf("%02d:%02d:%02d", hour, minute, second)
    formattedRuntime = datetime[1] " " converted_time

    record_id = formattedRuntime testID
    gsub(/[^0-9]/, "", record_id)

    if (record_id in data) {
        split(data[record_id], fields, ",")
        start_date_time = fields[1]

        cmd = "date -d \"" start_date_time "\" +%s.%3N"
        cmd | getline start_epoch
        close(cmd)

        cmd = "date -d \"" end_date_time "\" +%s.%3N"
        cmd | getline end_epoch
        close(cmd)

        total_test_time = sprintf("%.3f", end_epoch - start_epoch)
        print start_date_time "," end_date_time "," total_test_time "," testID "," monitorSet "," formattedRuntime "," record_id >> "testeng_test_times.csv"

        delete data[record_id]
    }
}

/^[0-9]{2}\/[0-9]{2}\/[0-9]{4}/ {
    timestamp = $1 " " $2
    in_block = 1
    agent_status = commeng_status = total_mem = used_mem = available_mem = ""
    free_mem_pct = commeng_pid = txeng_pid = testeng_pid = ""
}

/^Checking for Agent service hang/ { getline; agent_status = $1 }
/^Checking for sustained Harmony CommEng not running/ { getline; commeng_status = $1 }
/^Mem:/ {
    total_mem = $2
    used_mem = $3
    available_mem = $7
}

/CommEng\.dll/ { commeng_pid = $2 }
/TxEng\.dll/ { txeng_pid = $2 }
/TestEng\.dll/ { testeng_pid = $2 }

/^Free Memory percentage:/ {
    if (in_block) {
        free_mem_pct = int($4 * 100)
        print timestamp "," agent_status "," commeng_status "," total_mem "," used_mem "," available_mem "," free_mem_pct "," commeng_pid "," txeng_pid "," testeng_pid >> "sns_defib_analysis.csv"
        in_block = 0
    }
}
