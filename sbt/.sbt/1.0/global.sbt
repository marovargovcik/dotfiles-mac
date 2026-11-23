// `sbt --client` starts a server per project that otherwise never exits; one
// per worktree fills RAM and swap. Idle means no command (Metals' BSP compiles
// count), and the next `sbt --client` starts a fresh one.
Global / serverIdleTimeout := Some(scala.concurrent.duration.Duration(15, "min"))
