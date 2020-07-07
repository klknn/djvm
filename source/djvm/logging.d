module djvm.logging;

/// Reports the info.
@trusted
void info(
    size_t line = __LINE__,
    string modu = __MODULE__,
    Args...)
    (const(char)* fmt, Args args)
{
  import core.stdc.stdio : stderr, fprintf;
  import core.stdc.stdlib : exit;

  stderr.fprintf("[INFO %s:%d] ", &modu[0], line);
  stderr.fprintf(fmt, args);
  stderr.fprintf("\n");
}

/// Reports the error.
@trusted
void error(
    size_t line = __LINE__,
    string modu = __MODULE__,
    Args...)
    (const(char)* fmt, Args args)
{
  import core.stdc.stdio : stderr, fprintf;
  import core.stdc.stdlib : exit;

  stderr.fprintf("[ERROR %s]%d] ", &modu[0], line);
  stderr.fprintf(fmt, args);
  stderr.fprintf("\n");

  // prefer assert in debug because of stacktrace
  debug assert(false);
  else exit(1);
}
