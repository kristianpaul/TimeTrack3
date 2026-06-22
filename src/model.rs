use serde::{Deserialize, Serialize};
use chrono::{DateTime, Local};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Record {
    pub description: String,
    pub start: DateTime<Local>,
    pub end: Option<DateTime<Local>>,
}

impl Record {
    pub fn new(description: String) -> Self {
        Self {
            description,
            start: Local::now(),
            end: None,
        }
    }

    pub fn duration(&self) -> f64 {
        let end = self.end.unwrap_or(Local::now());
        (end - self.start).num_seconds() as f64
    }

    pub fn duration_str(&self) -> String {
        let secs = self.duration() as u64;
        let hours = secs / 3600;
        let mins = (secs % 3600) / 60;
        let seconds = secs % 60;
        if hours > 0 {
            format!("{:02}:{:02}:{:02}", hours, mins, seconds)
        } else {
            format!("{:02}:{:02}", mins, seconds)
        }
    }
}