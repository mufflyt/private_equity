# Cycle 1 -- 4 BVA, 3 semantic, 3 adversarial.
# Targets the office-blocking keys, because they decide which clinics are called and
# therefore control the "exactly two calls per office" guarantee the COMIRB protocol makes.

addr_row <- function(adr, city = "MIAMI", state = "FL", zip = "33130", ...) {
  d <- data.frame(`NPPES Address 1` = adr, `NPPES City` = city,
                  `NPPES State` = state, `NPPES Zip` = zip,
                  check.names = FALSE, stringsAsFactors = FALSE)
  extra <- list(...)
  for (nm in names(extra)) d[[nm]] <- extra[[nm]]
  d
}

# ---------------------------------------------------------------- BVA (4)

test_that("BVA: phone_key boundary sits exactly at 10 digits", {
  expect_true(is.na(phone_key("123456789")),
              info = "9 digits is not dialable and must not become a blocking key")
  expect_equal(phone_key("1234567890"), "1234567890")
  expect_equal(phone_key("11234567890"), "1234567890",
               info = "11-digit numbers keep the last 10, dropping the country code")
  expect_true(is.na(phone_key("")))
  expect_true(is.na(phone_key(NA)))
  expect_equal(phone_key("(305) 273-4641 ext 2"), "0527346412",
               info = "documents that extensions corrupt the key; callers must strip them first")
})

test_that("BVA: address_key requires exactly five ZIP digits", {
  expect_true(is.na(address_key(addr_row("100 MAIN ST", zip = "3313"))),
              info = "4-digit ZIP is not a valid key component")
  expect_match(address_key(addr_row("100 MAIN ST", zip = "33130")), "_33130$")
  expect_match(address_key(addr_row("100 MAIN ST", zip = "331304364")), "_33130$",
               info = "ZIP+4 truncates to the 5-digit prefix")
  expect_match(address_key(addr_row("100 MAIN ST", zip = "33130.0")), "_33130$",
               info = "pandas float ZIPs must not lose the fifth digit")
})

test_that("BVA: npi_key strips only a float suffix, never a real digit", {
  expect_equal(npi_key("1003038688.0"), "1003038688")
  expect_equal(npi_key("1003038688.00"), "1003038688")
  expect_equal(npi_key("1003038688"), "1003038688")
  expect_equal(npi_key("  1003038688.0  "), "1003038688")
  expect_equal(npi_key("10030386880"), "10030386880",
               info = "a trailing zero that is part of the NPI must survive")
})

test_that("BVA: key builders accept zero-row input without erroring", {
  empty <- addr_row(character(0), city = character(0), state = character(0), zip = character(0))
  expect_equal(length(address_key(empty)), 0L)
  expect_equal(length(phone_key(character(0))), 0L)
  expect_equal(length(npi_key(character(0))), 0L)
})

# ---------------------------------------------------------------- semantic (3)

test_that("semantic: distinct streets sharing a suite-token prefix get distinct keys", {
  # The suite-stripping alternation contains FL and NO. Without word boundaries these
  # match the start of real street names and the greedy [0-9A-Z]* eats the rest, so
  # unrelated Miami addresses collapse into one office and get wrongly de-duplicated.
  flagler  <- address_key(addr_row("100 FLAGLER ST"))
  flamingo <- address_key(addr_row("100 FLAMINGO AVE"))
  florida  <- address_key(addr_row("100 FLORIDA BLVD"))
  nolan    <- address_key(addr_row("100 NOLAN RD"))
  north    <- address_key(addr_row("100 NORTH RD"))
  sterling <- address_key(addr_row("100 STERLING WAY"))

  expect_false(flagler == flamingo,
               info = "Flagler St and Flamingo Ave are different offices")
  expect_false(flagler == florida,
               info = "Flagler St and Florida Blvd are different offices")
  expect_false(nolan == north,
               info = "Nolan Rd and North Rd are different offices")
  expect_false(flagler == sterling,
               info = "STE must not swallow STERLING")
})

test_that("semantic: suite designators are stripped so one building is one office", {
  a <- address_key(addr_row("100 MAIN ST SUITE 400"))
  b <- address_key(addr_row("100 MAIN ST SUITE 900"))
  c <- address_key(addr_row("100 MAIN ST STE 400"))
  d <- address_key(addr_row("100 MAIN ST FL 2"))
  expect_equal(a, b, info = "different suites in one building are one office")
  expect_equal(a, c, info = "STE and SUITE are the same designator")
  expect_equal(a, d, info = "a floor designator is not part of the street address")
})

test_that("semantic: npi_key is idempotent", {
  x <- c("1003038688.0", "1003038688", "  1912969700.00 ", NA)
  expect_equal(npi_key(npi_key(x)), npi_key(x),
               info = "normalising twice must not differ from normalising once")
})

# ---------------------------------------------------------------- adversarial (3)

test_that("adversarial: unusable values never collide with each other", {
  # De-duplication treats equal keys as the same office. If two different unknown
  # addresses or two unusable phones both produced "" they would be merged.
  expect_true(is.na(address_key(addr_row("", zip = "33130"))))
  expect_true(is.na(address_key(addr_row("100 MAIN ST", city = "N/A"))))
  expect_true(is.na(address_key(addr_row("100 MAIN ST", state = "NAN"))))
  expect_true(all(is.na(phone_key(c("", "abc", "12345")))),
              info = "unusable phones must be NA, not a shared truncated key")
})

test_that("adversarial: absent columns and blank columns behave identically", {
  with_blank <- addr_row("100 MAIN ST", `Scraped Address` = "", `DAC City` = "N/A")
  without    <- addr_row("100 MAIN ST")
  expect_equal(address_key(with_blank), address_key(without),
               info = "a blank optional column must not change the key")
})

test_that("adversarial: factor input yields labels, not integer level codes", {
  f <- factor(c("1003038688.0", "1912969700"))
  expect_equal(npi_key(f), c("1003038688", "1912969700"),
               info = "a factor NPI column must not silently become 1,2")
  pf <- factor(c("305-273-4641", "212-555-0100"))
  expect_equal(phone_key(pf), c("3052734641", "2125550100"))
})

# ---------------------------------------------------------------- col_ci

test_that("col_ci finds a column whatever its case", {
  d <- data.frame(Latitude = 1:2, longitude = 3:4)
  expect_equal(col_ci(d, "latitude"),  1:2)
  expect_equal(col_ci(d, "LATITUDE"),  1:2)
  expect_equal(col_ci(d, "Longitude"), 3:4)
})

test_that("adversarial: col_ci returns NULL rather than a partial match", {
  # R's `$` prefix-matches, so db$Lat would silently return Latitude while db$Latitude on a
  # lowercase build returns NULL. Both behaviours caused real failures; neither is wanted here.
  d <- data.frame(Latitude = 1:2)
  expect_null(col_ci(d, "lat"))
  expect_null(col_ci(d, "absent"))
})

test_that("BVA: col_ci on a frame with no columns is NULL, not an error", {
  expect_null(col_ci(data.frame(), "latitude"))
})
