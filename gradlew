#!/bin/sh
# Copyright 2015-2021 the original authors. Apache 2.0 License.
# Gradle start up script for POSIX — Gradle 8.6

##############################################################################
# Resolve APP_HOME to the project root (directory that contains this script)
##############################################################################
app_path=$0

# Follow symlinks
while [ -h "$app_path" ] ; do
    ls=$( ls -ld "$app_path" )
    link=${ls#*' -> '}
    case $link in
        /*)  app_path=$link ;;
        *)   app_path=${app_path%"${app_path##*/}"}$link ;;
    esac
done

# Strip the script filename — what remains is the directory (with trailing /)
# Then cd into it so pwd -P gives the canonical absolute path.
# NOTE: no ".." here — APP_HOME IS the project root, not its parent.
APP_HOME=$( cd "${app_path%"${app_path##*/}"}" && pwd -P ) || exit

APP_NAME="Gradle"
APP_BASE_NAME=${0##*/}

# JVM options — single-quoted so eval below expands them correctly
DEFAULT_JVM_OPTS='"-Xmx64m" "-Xms64m"'

warn() { echo "$*" >&2; }
die()  { echo; echo "$*" >&2; echo; exit 1; }

##############################################################################
# Find java
##############################################################################
if [ -n "$JAVA_HOME" ] ; then
    JAVACMD="$JAVA_HOME/bin/java"
    [ -x "$JAVACMD" ] || die "ERROR: JAVA_HOME points to an invalid directory: $JAVA_HOME"
else
    JAVACMD=java
    command -v java >/dev/null 2>&1 || die "ERROR: JAVA_HOME not set and 'java' not found in PATH."
fi

##############################################################################
# Raise fd limit (best-effort)
##############################################################################
case "$( uname )" in CYGWIN* | MSYS* | MINGW*) ;; *)
    MAX_FD=$( ulimit -H -n 2>/dev/null ) && ulimit -n "$MAX_FD" 2>/dev/null || true
    ;;
esac

##############################################################################
# Build command line — eval expands quoted JVM opts correctly
##############################################################################
CLASSPATH="$APP_HOME/gradle/wrapper/gradle-wrapper.jar"

# shellcheck disable=SC2086
eval set -- \
    $DEFAULT_JVM_OPTS \
    $JAVA_OPTS \
    $GRADLE_OPTS \
    "\"-Dorg.gradle.appname=$APP_BASE_NAME\"" \
    -classpath "\"$CLASSPATH\"" \
    org.gradle.wrapper.GradleWrapperMain \
    "$@"

exec "$JAVACMD" "$@"
