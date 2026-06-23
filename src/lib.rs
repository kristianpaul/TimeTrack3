use std::ffi::{c_char, CStr, CString};
use std::path::PathBuf;
use std::fs;
use std::sync::Mutex;
use chrono::Local;

mod model;

pub use model::Record;

struct State {
    records: Vec<Record>,
    current: Option<Record>,
    data_path: PathBuf,
}

static STATE: Mutex<Option<State>> = Mutex::new(None);

fn ensure_state() {
    let mut state = STATE.lock().unwrap();
    if state.is_none() {
        let data_dir = get_data_dir();
        let _ = fs::create_dir_all(&data_dir);
        let data_path = data_dir.join("records.json");
        let all_records = if data_path.exists() {
            let content = fs::read_to_string(&data_path).unwrap_or_default();
            serde_json::from_str(&content).unwrap_or_default()
        } else {
            Vec::new()
        };

        // Keep only today's records + the current tracking task
        let today = Local::now().date_naive();
        let today_records: Vec<Record> = all_records.into_iter()
            .filter(|r: &Record| r.start.date_naive() == today)
            .collect();

        *state = Some(State {
            records: today_records,
            current: None,
            data_path,
        });
    }
}

fn save() {
    let state = STATE.lock().unwrap();
    let s = state.as_ref().unwrap();
    let all: Vec<Record> = s.records.iter()
        .chain(s.current.iter())
        .cloned()
        .collect();
    if let Ok(content) = serde_json::to_string_pretty(&all) {
        let _ = fs::write(&s.data_path, content);
    }
}

fn get_data_dir() -> PathBuf {
    let mut path = std::env::var("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/tmp"));
    path.push(".local/share/timetrack3");
    path
}

fn make_cstr(s: String) -> *mut c_char {
    CString::new(s).unwrap().into_raw()
}

fn csv_escape(s: &str) -> String {
    let escaped = s.replace('\"', "\"\"");
    format!("\"{}\"", escaped)
}

#[no_mangle]
pub extern "C" fn tt_init() {
    ensure_state();
}

#[no_mangle]
pub extern "C" fn tt_start(description: *const c_char) -> *mut c_char {
    ensure_state();
    let desc = unsafe {
        if description.is_null() {
            String::from("Untitled")
        } else {
            CStr::from_ptr(description)
                .to_string_lossy()
                .into_owned()
        }
    };

    let result;
    {
        let mut state = STATE.lock().unwrap();
        let s = state.as_mut().unwrap();
        s.current = Some(Record::new(desc));
    }
    save();
    result = "started".to_string();

    make_cstr(result)
}

#[no_mangle]
pub extern "C" fn tt_stop() -> *mut c_char {
    ensure_state();
    {
        let mut state = STATE.lock().unwrap();
        let s = state.as_mut().unwrap();
        if let Some(mut record) = s.current.take() {
            record.end = Some(Local::now());
            s.records.push(record);
        }
    }
    save();

    make_cstr("stopped".to_string())
}

#[no_mangle]
pub extern "C" fn tt_status() -> *mut c_char {
    ensure_state();
    let result = {
        let state = STATE.lock().unwrap();
        let s = state.as_ref().unwrap();
        if let Some(r) = &s.current {
            format!("tracking|{}|{}", r.description, r.duration_str())
        } else {
            "idle".to_string()
        }
    };
    make_cstr(result)
}

#[no_mangle]
pub extern "C" fn tt_history() -> *mut c_char {
    ensure_state();
    let result = {
        let state = STATE.lock().unwrap();
        let s = state.as_ref().unwrap();
        s.records.iter().rev().take(10).map(|r| {
            format!("{}|{}|{}", r.description, r.start.format("%H:%M"), r.duration_str())
        }).collect::<Vec<_>>().join("\n")
    };
    make_cstr(result)
}

#[no_mangle]
pub extern "C" fn tt_export_csv(date: *const c_char) -> *mut c_char {
    ensure_state();
    let date_str = unsafe {
        if date.is_null() {
            String::new()
        } else {
            CStr::from_ptr(date).to_string_lossy().into_owned()
        }
    };

    let result = {
        let state = STATE.lock().unwrap();
        let s = state.as_ref().unwrap();

        let target_date = if !date_str.is_empty() {
            chrono::NaiveDate::parse_from_str(&date_str, "%Y-%m-%d").ok()
        } else {
            None
        };

        let mut lines = vec!["Description,Start,End,Duration".to_string()];

        for r in &s.records {
            if let Some(target) = &target_date {
                if &r.start.date_naive() != target {
                    continue;
                }
            }

            let desc = csv_escape(&r.description);
            let start = r.start.format("%Y-%m-%d %H:%M:%S").to_string();
            let end = r.end
                .map(|e| e.format("%Y-%m-%d %H:%M:%S").to_string())
                .unwrap_or_default();
            let dur = r.duration_str();

            lines.push(format!("{},{},{},{}", desc, start, end, dur));
        }

        lines.join("\n")
    };
    make_cstr(result)
}

#[no_mangle]
pub extern "C" fn tt_rename(index: i32, new_name: *const c_char) -> *mut c_char {
    ensure_state();
    let name = unsafe {
        if new_name.is_null() {
            String::from("Untitled")
        } else {
            CStr::from_ptr(new_name).to_string_lossy().into_owned()
        }
    };

    let result = {
        let mut state = STATE.lock().unwrap();
        let s = state.as_mut().unwrap();
        let actual_index = s.records.len() - 1 - (index as usize);
        if actual_index < s.records.len() {
            s.records[actual_index].description = name;
            "renamed".to_string()
        } else {
            "error".to_string()
        }
    };
    save();
    make_cstr(result)
}

#[no_mangle]
pub extern "C" fn tt_delete(index: i32) -> *mut c_char {
    ensure_state();
    let result = {
        let mut state = STATE.lock().unwrap();
        let s = state.as_mut().unwrap();
        let actual_index = s.records.len() - 1 - (index as usize);
        if actual_index < s.records.len() {
            s.records.remove(actual_index);
            "deleted".to_string()
        } else {
            "error".to_string()
        }
    };
    save();
    make_cstr(result)
}

#[no_mangle]
pub extern "C" fn tt_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_records(count: usize) -> Vec<Record> {
        (0..count).map(|i| Record::new(format!("Task {}", i))).collect()
    }

    fn menu_index_to_record_index(menu_index: usize, records_len: usize) -> Option<usize> {
        if records_len == 0 || menu_index >= records_len {
            return None;
        }
        Some(records_len - 1 - menu_index)
    }

    #[test]
    fn test_index_mapping_three() {
        assert_eq!(menu_index_to_record_index(0, 3), Some(2));
        assert_eq!(menu_index_to_record_index(1, 3), Some(1));
        assert_eq!(menu_index_to_record_index(2, 3), Some(0));
    }

    #[test]
    fn test_index_mapping_single() {
        assert_eq!(menu_index_to_record_index(0, 1), Some(0));
        assert_eq!(menu_index_to_record_index(1, 1), None);
    }

    #[test]
    fn test_index_mapping_empty() {
        assert_eq!(menu_index_to_record_index(0, 0), None);
    }

    #[test]
    fn test_index_mapping_ten() {
        assert_eq!(menu_index_to_record_index(0, 10), Some(9));
        assert_eq!(menu_index_to_record_index(9, 10), Some(0));
        assert_eq!(menu_index_to_record_index(10, 10), None);
    }

    #[test]
    fn test_delete_newest() {
        let mut records = make_records(3);
        let idx = menu_index_to_record_index(0, records.len()).unwrap();
        assert_eq!(records[idx].description, "Task 2");
        records.remove(idx);
        assert_eq!(records[0].description, "Task 0");
        assert_eq!(records[1].description, "Task 1");
    }

    #[test]
    fn test_delete_middle() {
        let mut records = make_records(3);
        let idx = menu_index_to_record_index(1, records.len()).unwrap();
        assert_eq!(records[idx].description, "Task 1");
        records.remove(idx);
        assert_eq!(records[0].description, "Task 0");
        assert_eq!(records[1].description, "Task 2");
    }

    #[test]
    fn test_rename() {
        let mut records = make_records(3);
        let idx = menu_index_to_record_index(0, records.len()).unwrap();
        records[idx].description = "Renamed".to_string();
        assert_eq!(records[2].description, "Renamed");
        assert_eq!(records[0].description, "Task 0");
    }

    #[test]
    fn test_csv_escape() {
        assert_eq!(csv_escape("hello"), "\"hello\"");
        assert_eq!(csv_escape("say \"hi\""), "\"say \"\"hi\"\"\"");
        assert_eq!(csv_escape("a,b,c"), "\"a,b,c\"");
    }
}