# Architecture

Big Cat Wubi is a Windows packaging and configuration layer around Rime/Weasel.
It does not fork Weasel or librime.

```text
Windows text service
  -> Weasel 0.17.4
     -> librime 1.13.1
        -> Big Cat Wubi schema
           -> pinned wubi86 dictionary
           -> local user dictionary
```

The bundled installer deploys project-owned schema and branding files, verifies
pinned upstream inputs, and records enough ownership state for targeted uninstall.
Runtime configuration and UserDB files remain in the standard Rime user directory.

Backup and restore use official librime interfaces plus strict public-policy
guards. They never hot-copy a live LevelDB directory. Restore validates package
bytes and identity before mutation and creates a safety backup before changing an
existing target.

Network retrieval is not part of the bundled installer or normal runtime. The
source installer can retrieve the official `rime-wubi` dependency only when the
user explicitly requests that online path.
