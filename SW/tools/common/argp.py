import argparse
import sys


class ArgParser(argparse.ArgumentParser):
    def error(self, message):
        self.print_help()
        sys.stderr.write('\nerror: %s\n' % message)
        sys.exit(1)
