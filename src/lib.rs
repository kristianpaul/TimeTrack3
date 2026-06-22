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
        let records = if data_path.exists() {
            let content = fs::read_to_string(&data_path).unwrap_or_default();
            serde_json::from_str(&content).unwrap_or_default()
        } else {
            Vec::new()
        };
        *state = Some(State {
            records,
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
pub extern "C" fn tt_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}