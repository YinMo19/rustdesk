use anyhow::{Context, Result};
use hbb_common::message_proto::*;
use portable_pty::{Child, CommandBuilder, PtySize};
use std::io::{Read, Write};

pub struct TerminalService {
    id: i32,
    pty_pair: Option<portable_pty::PtyPair>,
    child: Option<Box<dyn Child + std::marker::Send + Sync>>,
    writer: Option<Box<dyn Write + Send>>,
}

impl TerminalService {
    pub fn new(id: i32) -> Self {
        TerminalService {
            id,
            pty_pair: None,
            child: None,
            writer: None,
        }
    }

    pub fn handle_request(&mut self, req: &TerminalRequest) -> Result<TerminalResponse> {
        let mut response = TerminalResponse::new();

        match &req.union {
            Some(terminal_request::Union::Open(open)) => self.handle_open(open, &mut response),
            Some(terminal_request::Union::Resize(resize)) => {
                self.handle_resize(resize, &mut response)
            }
            Some(terminal_request::Union::Data(data)) => self.handle_data(data, &mut response),
            Some(terminal_request::Union::Close(close)) => self.handle_close(close, &mut response),
            None => Ok(()),
            _ => Ok(()),
        }?;

        Ok(response)
    }

    fn handle_open(&mut self, open: &OpenTerminal, response: &mut TerminalResponse) -> Result<()> {
        if self.pty_pair.is_some() {
            let mut opened = TerminalOpened::new();
            opened.success = false;
            opened.message = "Terminal already open".to_string();
            response.set_opened(opened);
            return Ok(());
        }

        let pty_size = PtySize {
            rows: open.rows as u16,
            cols: open.cols as u16,
            pixel_width: 0,
            pixel_height: 0,
        };

        let pty_system = portable_pty::native_pty_system();
        let pty_pair = pty_system.openpty(pty_size).context("Failed to open PTY")?;

        let mut cmd = CommandBuilder::new(&open.shell);
        for env in &open.env {
            if let Some((key, value)) = env.split_once('=') {
                cmd.env(key, value);
            }
        }

        let child = pty_pair
            .slave
            .spawn_command(cmd)
            .context("Failed to spawn command")?;

        let writer = pty_pair
            .master
            .take_writer()
            .context("Failed to get writer")?;

        self.pty_pair = Some(pty_pair);
        self.child = Some(child);
        self.writer = Some(writer);

        let mut opened = TerminalOpened::new();
        opened.success = true;
        opened.message = "Terminal opened".to_string();
        opened.pid = self
            .child
            .as_ref()
            .and_then(|c| c.process_id())
            .unwrap_or(0) as u32;
        response.set_opened(opened);

        Ok(())
    }

    fn handle_resize(
        &mut self,
        resize: &ResizeTerminal,
        _response: &mut TerminalResponse,
    ) -> Result<()> {
        if let Some(pty_pair) = &self.pty_pair {
            pty_pair.master.resize(PtySize {
                rows: resize.rows as u16,
                cols: resize.cols as u16,
                pixel_width: 0,
                pixel_height: 0,
            })?;
        }
        Ok(())
    }

    fn handle_data(&mut self, data: &TerminalData, response: &mut TerminalResponse) -> Result<()> {
        if let Some(writer) = &mut self.writer {
            writer.write_all(&data.data)?;
            writer.flush()?;

            // Echo the data back as output
            let mut resp_data = TerminalData::new();
            resp_data.data = data.data.clone();
            response.set_data(resp_data);
        }
        Ok(())
    }

    fn handle_close(
        &mut self,
        close: &CloseTerminal,
        response: &mut TerminalResponse,
    ) -> Result<()> {
        let exit_code = if let Some(child) = &mut self.child {
            if close.force {
                child.kill()?;
                -1 // -1 indicates forced termination
            } else {
                let status = child.wait()?;
                status.exit_code() as i32
            }
        } else {
            0
        };

        let mut closed = TerminalClosed::new();
        closed.exit_code = exit_code;
        response.set_closed(closed);

        self.pty_pair = None;
        self.child = None;
        self.writer = None;

        Ok(())
    }

    pub fn read_output(&mut self) -> Result<Option<TerminalResponse>> {
        if let Some(pty_pair) = &self.pty_pair {
            let mut reader = pty_pair.master.try_clone_reader()?;
            let mut buf = vec![0; 1024];

            match reader.read(&mut buf) {
                Ok(n) if n > 0 => {
                    let mut response = TerminalResponse::new();
                    let mut data = TerminalData::new();
                    data.data = bytes::Bytes::from(buf[..n].to_vec());
                    response.set_data(data);
                    Ok(Some(response))
                }
                Ok(_) => Ok(None), // EOF
                Err(e) => {
                    let mut response = TerminalResponse::new();
                    let mut error = TerminalError::new();
                    error.message = format!("Read error: {}", e);
                    response.set_error(error);
                    Ok(Some(response))
                }
            }
        } else {
            Ok(None)
        }
    }
}
