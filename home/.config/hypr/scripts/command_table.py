"""A command line described by a table {name: Command}: one check of the arguments, one usage text."""
import json
import re
import sys
from collections.abc import Callable
from dataclasses import dataclass


@dataclass(frozen=True)
class Command:
    """handler(*arguments) returns the exit status, None for 0. synopsis shows the arguments the way
    usage prints them and is also what they are checked against: <value>, a literal word, [<optional
    value>] after the required ones, [--option] for any number of options after them. errors are what
    the handler raises about a thing that does not fit: a line on stderr and status 1."""
    handler: Callable
    synopsis: str
    summary: str
    errors: tuple = ()

    def accepts(self, arguments):
        words = re.findall(r"\[[^\]]*\]|\S+", self.synopsis)
        required = [word for word in words if not word.startswith("[")]
        optional = [word for word in words if word.startswith("[<")]
        takes_options = any(word.startswith("[--") for word in words)
        if len(arguments) < len(required):
            return False
        if len(arguments) > len(required) + len(optional) and not takes_options:
            return False
        return all(word.startswith("<") or word == argument for word, argument in zip(required, arguments))


def usage(program, commands):
    return "\n".join(f"  {program} {name} {command.synopsis}".rstrip() + f"\n      {command.summary}"
                     for name, command in commands.items())


def run(program, commands, argv):
    """The exit status of the command argv starts with: 2 and the usage on stderr when there is no such
    command or its arguments do not fit, 1 and the reason on stderr when the handler fails with one of
    the command's errors."""
    command = commands.get(argv[0]) if argv else None
    if command is None or not command.accepts(argv[1:]):
        print(usage(program, commands), file=sys.stderr)
        return 2
    try:
        return command.handler(*argv[1:]) or 0
    except command.errors as error:
        print(error, file=sys.stderr)
        return 1


def printing(function):
    """function with its result printed as it is."""
    return lambda *args: print(function(*args))


def printing_json(function):
    """function with its result printed as one line of JSON, the form the windows read."""
    return lambda *args: print(json.dumps(function(*args), ensure_ascii=False))
