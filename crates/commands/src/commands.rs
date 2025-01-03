pub mod admin;
pub mod api;
pub mod autoproxy;
pub mod checks;
pub mod commands;
pub mod config;
pub mod dashboard;
pub mod debug;
pub mod fun;
pub mod group;
pub mod help;
pub mod import_export;
pub mod member;
pub mod message;
pub mod misc;
pub mod random;
pub mod server_config;
pub mod switch;
pub mod system;

use smol_str::SmolStr;

use crate::{command, token::Token};

#[derive(Clone)]
pub struct Command {
    // TODO: fix hygiene
    pub tokens: Vec<Token>,
    pub help: SmolStr,
    pub cb: SmolStr,
}

impl Command {
    pub fn new(
        tokens: impl IntoIterator<Item = Token>,
        help: impl Into<SmolStr>,
        cb: impl Into<SmolStr>,
    ) -> Self {
        Self {
            tokens: tokens.into_iter().collect(),
            help: help.into(),
            cb: cb.into(),
        }
    }
}

#[macro_export]
macro_rules! command {
    ([$($v:expr),+], $cb:expr, $help:expr) => {
        $crate::commands::Command::new([$($v.clone()),*], $help, $cb)
    };
}

pub fn all() -> Vec<Command> {
    (help::cmds())
        .chain(system::cmds())
        .chain(member::cmds())
        .collect()
}