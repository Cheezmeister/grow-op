Reading from stdin:

  $ echo "TestApp: bogus" | $TESTDIR/grow -
  Failed to fetch 'bogus'

Multiple failures

  $ echo "TestApp: poppycock\nOtherApp: hogwash" | $TESTDIR/grow -
  Failed to fetch 'poppycock,hogwash'
