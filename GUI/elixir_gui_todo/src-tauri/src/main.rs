use std::{process::Child, sync::Mutex};

#[cfg(not(debug_assertions))]
use std::{
    net::{SocketAddr, TcpStream},
    path::PathBuf,
    process::Command,
    thread,
    time::{Duration, Instant},
};

use tauri::{Manager, WindowEvent};

#[cfg(not(debug_assertions))]
const DESKTOP_PORT: u16 = 4017;

struct BackendProcess(Mutex<Option<Child>>);

fn main() {
    tauri::Builder::default()
        .setup(|_app| {
            #[cfg(not(debug_assertions))]
            start_backend(_app)?;

            Ok(())
        })
        .on_window_event(|window, event| {
            if matches!(event, WindowEvent::CloseRequested { .. }) {
                if let Some(state) = window.try_state::<BackendProcess>() {
                    if let Ok(mut child) = state.0.lock() {
                        if let Some(mut child) = child.take() {
                            let _ = child.kill();
                            let _ = child.wait();
                        }
                    }
                }
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running Elixir Todo desktop shell");
}

#[cfg(not(debug_assertions))]
fn start_backend(app: &mut tauri::App) -> Result<(), Box<dyn std::error::Error>> {
    let release_bin = release_bin(app)?;
    let mut command = Command::new(release_bin);

    command
        .env("ELIXIR_GUI_TODO_DESKTOP", "true")
        .env("PHX_SERVER", "true")
        .env("PORT", DESKTOP_PORT.to_string());

    let child = command.spawn()?;
    app.manage(BackendProcess(Mutex::new(Some(child))));

    if let Some(window) = app.get_webview_window("main") {
        thread::spawn(move || {
            if wait_for_backend(Duration::from_secs(20)) {
                let _ = window.eval(&format!(
                    "window.location.replace('http://127.0.0.1:{DESKTOP_PORT}/')"
                ));
                let _ = window.show();
            }
        });
    }

    Ok(())
}

#[cfg(not(debug_assertions))]
fn release_bin(app: &tauri::App) -> Result<PathBuf, Box<dyn std::error::Error>> {
    let resource_dir = app.path().resource_dir()?;

    #[cfg(windows)]
    let bin = resource_dir
        .join("elixir_gui_todo")
        .join("bin")
        .join("elixir_gui_todo.bat");

    #[cfg(not(windows))]
    let bin = resource_dir
        .join("elixir_gui_todo")
        .join("bin")
        .join("elixir_gui_todo");

    Ok(bin)
}

#[cfg(not(debug_assertions))]
fn wait_for_backend(timeout: Duration) -> bool {
    let started_at = Instant::now();
    let address = SocketAddr::from(([127, 0, 0, 1], DESKTOP_PORT));

    while started_at.elapsed() < timeout {
        if TcpStream::connect_timeout(&address, Duration::from_millis(250)).is_ok() {
            return true;
        }

        thread::sleep(Duration::from_millis(150));
    }

    false
}
