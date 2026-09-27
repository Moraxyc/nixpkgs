use std::{
    collections::HashSet,
    fs,
    os::unix::fs::{symlink, PermissionsExt},
    path::{Path, PathBuf},
};

use eyre::{bail, Context, Result};
use walkdir::WalkDir;

const ETC: &str = "/etc";
const STATIC: &str = "/etc/static";

fn with_suffix(path: &Path, suffix: &str) -> PathBuf {
    let mut s = path.as_os_str().to_os_string();
    s.push(suffix);
    PathBuf::from(s)
}

fn atomic_symlink(source: &Path, target: &Path) -> std::io::Result<()> {
    let tmp = with_suffix(target, ".tmp");
    let _ = fs::remove_file(&tmp);
    symlink(source, &tmp)?;
    if let Err(e) = fs::rename(&tmp, target) {
        let _ = fs::remove_file(&tmp);
        return Err(e);
    }
    Ok(())
}

// Returns true if `path` points into /etc/static, meaning it is either a
// symlink whose target lives under /etc/static/, or a directory whose every
// child is itself static.
fn is_static(path: &Path) -> bool {
    let Ok(meta) = fs::symlink_metadata(path) else {
        return false;
    };

    if meta.file_type().is_symlink() {
        return fs::read_link(path)
            .ok()
            .and_then(|target| target.to_str().map(|s| s.starts_with("/etc/static/")))
            .unwrap_or(false);
    }

    if meta.is_dir() {
        let Ok(entries) = fs::read_dir(path) else {
            return false;
        };
        return entries
            .filter_map(|e| e.ok())
            .all(|entry| is_static(&entry.path()));
    }

    false
}

// Remove dangling symlinks in /etc that point into /etc/static but whose
// corresponding /etc/static entry no longer exists. /etc/nixos is pruned.
fn cleanup() {
    let nixos = Path::new("/etc/nixos");
    for entry in WalkDir::new(ETC)
        .into_iter()
        .filter_entry(|e: &walkdir::DirEntry| e.path() != nixos)
    {
        let Ok(entry) = entry else {
            continue;
        };
        let path = entry.path();
        if path == Path::new(ETC) {
            continue;
        }

        let is_symlink = fs::symlink_metadata(path)
            .map(|m| m.file_type().is_symlink())
            .unwrap_or(false);
        if !is_symlink {
            continue;
        }

        let target = match fs::read_link(path) {
            Ok(t) => t,
            Err(_) => continue,
        };
        let Some(target_str) = target.to_str() else {
            continue;
        };
        if !target_str.starts_with(STATIC) {
            continue;
        }

        let static_entry = Path::new(STATIC).join(path.strip_prefix("/etc/").unwrap_or(path));
        let exists = fs::symlink_metadata(&static_entry)
            .map(|m| m.file_type().is_symlink())
            .unwrap_or(false);
        if !exists {
            eprintln!("removing obsolete symlink ‘{}’...", path.display());
            let _ = fs::remove_file(path);
        }
    }
}

fn resolve_id(s: &str, lookup: fn(&str) -> Option<u32>) -> u32 {
    if let Some(rest) = s.strip_prefix('+') {
        rest.parse().unwrap_or(0)
    } else {
        lookup(s).unwrap_or(0)
    }
}

fn lookup_uid(name: &str) -> Option<u32> {
    nix::unistd::User::from_name(name)
        .ok()
        .flatten()
        .map(|u| u.uid.as_raw())
}

fn lookup_gid(name: &str) -> Option<u32> {
    nix::unistd::Group::from_name(name)
        .ok()
        .flatten()
        .map(|g| g.gid.as_raw())
}

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let Some(etc) = args.next() else {
        bail!("missing argument: path to the etc tree");
    };
    let etc = Path::new(&etc);
    let static_path = Path::new(STATIC);

    // Atomically update /etc/static to point at the etc files of the current
    // configuration.
    atomic_symlink(etc, static_path).context("Failed to update /etc/static")?;

    cleanup();

    // Use /etc/.clean to keep track of copied files.
    let old_copied: Vec<String> = fs::read_to_string("/etc/.clean")
        .map(|s| s.lines().map(String::from).collect())
        .unwrap_or_default();

    let in_nixos_enter = std::env::var("IN_NIXOS_ENTER").is_ok();
    let mut created: HashSet<String> = HashSet::new();
    let mut copied: Vec<String> = Vec::new();

    for entry in WalkDir::new(etc) {
        let entry = match entry {
            Ok(e) => e,
            Err(e) => {
                eprintln!("{e}");
                continue;
            }
        };
        let path = entry.path();
        if path == etc {
            continue;
        }
        let rel = match path.strip_prefix(etc) {
            Ok(r) => r,
            Err(_) => continue,
        };
        let fn_ = rel.to_string_lossy();

        // nixos-enter sets up /etc/resolv.conf as a bind mount, so skip it.
        if fn_ == "resolv.conf" && in_nixos_enter {
            continue;
        }

        let target = Path::new(ETC).join(rel);
        if let Some(parent) = target.parent() {
            fs::create_dir_all(parent).context("Failed to create target directory")?;
        }
        created.insert(fn_.to_string());

        let meta = fs::symlink_metadata(path).context("Failed to stat etc entry")?;

        // Rename doesn't work if target is directory.
        if meta.file_type().is_symlink() && target.is_dir() {
            if is_static(&target) {
                if let Err(e) = fs::remove_dir_all(&target) {
                    eprintln!("could not remove {target}: {e}", target = target.display());
                }
            } else {
                eprintln!(
                    "{} directory contains user files. Symlinking may fail.",
                    target.display()
                );
            }
        }

        let mode_path = with_suffix(path, ".mode");
        if mode_path.exists() {
            let mode = fs::read_to_string(&mode_path)
                .context("Failed to read mode")?
                .trim()
                .to_string();

            if mode == "direct-symlink" {
                let dest = fs::read_link(static_path.join(rel))?;
                if let Err(e) = atomic_symlink(&dest, &target) {
                    eprintln!("could not create symlink {}: {e}", target.display());
                }
            } else {
                let uid_s = fs::read_to_string(with_suffix(path, ".uid"))
                    .context("Failed to read uid")?
                    .trim()
                    .to_string();
                let gid_s = fs::read_to_string(with_suffix(path, ".gid"))
                    .context("Failed to read gid")?
                    .trim()
                    .to_string();

                let tmp = with_suffix(&target, ".tmp");
                let uid = resolve_id(&uid_s, lookup_uid);
                let gid = resolve_id(&gid_s, lookup_gid);

                if let Err(e) = fs::copy(static_path.join(rel), &tmp) {
                    eprintln!("could not copy to {tmp}: {e}", tmp = tmp.display());
                }
                if let Err(e) = nix::unistd::chown(&tmp, Some(uid.into()), Some(gid.into())) {
                    eprintln!("could not chown {tmp}: {e}", tmp = tmp.display());
                }
                if let Err(e) =
                    fs::set_permissions(&tmp, fs::Permissions::from_mode(parse_mode(&mode)?))
                {
                    eprintln!("could not chmod {tmp}: {e}", tmp = tmp.display());
                }
                if let Err(e) = fs::rename(&tmp, &target) {
                    eprintln!(
                        "could not create target {target}: {e}",
                        target = target.display()
                    );
                    let _ = fs::remove_file(&tmp);
                }
            }

            copied.push(fn_.to_string());
        } else if meta.file_type().is_symlink() {
            if let Err(e) = atomic_symlink(&static_path.join(rel), &target) {
                eprintln!("could not create symlink {}: {e}", target.display());
            }
        }
    }

    // Delete files that were copied in a previous version but not in the
    // current.
    for fn_ in &old_copied {
        if !created.contains(fn_) {
            let path = format!("/etc/{fn_}");
            eprintln!("removing obsolete file ‘{path}’...");
            let _ = fs::remove_file(&path);
        }
    }

    // Rewrite /etc/.clean.
    copied.sort_unstable();
    copied.dedup();
    let mut content = String::new();
    for fn_ in &copied {
        content.push_str(fn_);
        content.push('\n');
    }
    fs::write("/etc/.clean", content).context("Failed to rewrite /etc/.clean")?;

    // Create /etc/NIXOS tag if not exists. When /etc is not on a persistent
    // filesystem, it will be wiped after reboot, so we need to check and
    // re-create it during activation.
    let _ = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open("/etc/NIXOS")
        .context("Failed to create /etc/NIXOS")?;

    Ok(())
}

fn parse_mode(s: &str) -> Result<u32> {
    u32::from_str_radix(s.trim_start_matches("0o"), 8).with_context(|| format!("invalid mode: {s}"))
}
