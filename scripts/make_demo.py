#!/usr/bin/env python3
"""Builds an isolated demo environment for screenshots and manual testing.

Usage: scripts/make_demo.py <output-dir>
Creates <out>/library  (a Folio library with sample notes and sessions)
    and <out>/applebooks (a synthetic Apple Books container with sample books and highlights).
Run Folio against it with:
  open -n --env FOLIO_DATA_DIR=<out>/library --env FOLIO_APPLE_BOOKS_DIR=<out>/applebooks Folio.app
All notes are written for the demo; no real reading data is used.
"""
import json, os, shutil, sqlite3, sys, uuid, datetime

out = os.path.abspath(sys.argv[1])
shutil.rmtree(out, ignore_errors=True)
lib_dir, ab_dir = os.path.join(out, "library"), os.path.join(out, "applebooks")
os.makedirs(lib_dir); os.makedirs(os.path.join(ab_dir, "BKLibrary")); os.makedirs(os.path.join(ab_dir, "AEAnnotation"))
here = os.path.dirname(os.path.abspath(__file__))
base = json.load(open(os.path.join(here, "..", "Tests", "FolioTests", "Fixtures", "library-v1.json")))

now = datetime.datetime.now(datetime.timezone.utc)
def iso(d): return d.strftime("%Y-%m-%dT%H:%M:%S.000Z")
def note(kind, text, page=None, chapter=None, tags=(), days_ago=1):
    n = {"id": str(uuid.uuid4()).upper(), "created": iso(now - datetime.timedelta(days=days_ago)),
         "updated": iso(now - datetime.timedelta(days=days_ago)), "kind": kind, "text": text, "tags": list(tags), "links": []}
    if page: n["page"] = page
    if chapter: n["chapter"] = chapter
    return n

notes = {
    "Atomic Habits": [note("lesson", "Small improvements **compound**: a 1% change repeated daily matters more than one big push.", 42, "1", ["compounding", "habits"]),
                      note("mentalModel", "Systems beat goals: design the environment so the good behaviour is the easy one.", None, "Intro", ["systems"], 3)],
    "Sapiens": [note("reflection", "Shared stories (money, nations, companies) let strangers cooperate at scale.", None, "Part 2", ["cooperation", "systems"], 5),
                note("question", "If institutions are shared fictions, what makes some last for centuries?", None, None, ["institutions"], 6)],
    "Dune": [note("takeaway", "Control of a scarce resource is control of the whole system around it.", None, None, ["power", "incentives"], 8)],
    "Project Hail Mary": [note("reflection", "Problem-solving under pressure: break it into experiments you can actually run today.", 180, None, ["thinking"], 2)],
    "Educated": [note("lesson", "Education is less about facts than about permission to reinterpret your own story.", None, None, ["identity"], 9)],
    "Circe": [note("reflection", "Transformation as a theme: power comes from patient craft, not birthright.", None, None, ["power", "craft"], 12)],
}
for b in base["books"]:
    b["notes"] = b.get("notes", []) + notes.get(b["title"], [])
base["version"] = 1
json.dump(base, open(os.path.join(lib_dir, "library.json"), "w"), indent=1)

# Synthetic Apple Books store: same tables/columns Folio reads (verified against Apple Books 7.6).
ref = datetime.datetime(2001, 1, 1, tzinfo=datetime.timezone.utc)
def cd(d): return (d - ref).total_seconds()
lib = sqlite3.connect(os.path.join(ab_dir, "BKLibrary", "BKLibrary-1-091020131601.sqlite"))
lib.execute("PRAGMA journal_mode=WAL")
lib.execute("""CREATE TABLE ZBKLIBRARYASSET (Z_PK INTEGER PRIMARY KEY, ZASSETID VARCHAR, ZTITLE VARCHAR, ZAUTHOR VARCHAR, ZGENRE VARCHAR,
  ZBOOKDESCRIPTION VARCHAR, ZLANGUAGE VARCHAR, ZYEAR VARCHAR, ZPAGECOUNT INTEGER, ZCONTENTTYPE INTEGER, ZREADINGPROGRESS FLOAT,
  ZBOOKHIGHWATERMARKPROGRESS FLOAT, ZISFINISHED INTEGER, ZDATEFINISHED TIMESTAMP, ZCREATIONDATE TIMESTAMP, ZISSAMPLE INTEGER,
  ZISHIDDEN INTEGER, ZISSTOREAUDIOBOOK INTEGER)""")
assets = [("DEMO-1", "Meditations", "Marcus Aurelius", "Philosophy", 0.42, 0, None),
          ("DEMO-2", "The Odyssey", "Homer", "Classics", 1.0, 1, now - datetime.timedelta(days=20)),
          ("DEMO-3", "Walden", "Henry David Thoreau", "Nature", 0.0, 0, None),
          ("DEMO-4", "Pride and Prejudice", "Jane Austen", "Fiction", 0.18, 0, None)]
for i, (aid, title, author, genre, prog, fin, fdate) in enumerate(assets):
    lib.execute("INSERT INTO ZBKLIBRARYASSET VALUES (?,?,?,?,?,NULL,'en',NULL,0,1,?,?,?,?,?,0,0,0)",
                (i + 1, aid, title, author, genre, prog, prog, fin, cd(fdate) if fdate else None, cd(now - datetime.timedelta(days=60))))
lib.commit(); lib.close()
ann = sqlite3.connect(os.path.join(ab_dir, "AEAnnotation", "AEAnnotation_v10312011_1727_local.sqlite"))
ann.execute("PRAGMA journal_mode=WAL")
ann.execute("""CREATE TABLE ZAEANNOTATION (Z_PK INTEGER PRIMARY KEY, ZANNOTATIONDELETED INTEGER, ZANNOTATIONSTYLE INTEGER, ZANNOTATIONTYPE INTEGER,
  ZANNOTATIONCREATIONDATE TIMESTAMP, ZANNOTATIONMODIFICATIONDATE TIMESTAMP, ZANNOTATIONASSETID VARCHAR, ZANNOTATIONLOCATION VARCHAR,
  ZANNOTATIONNOTE VARCHAR, ZANNOTATIONSELECTEDTEXT VARCHAR, ZANNOTATIONUUID VARCHAR, ZFUTUREPROOFING5 VARCHAR)""")
hl = [("DEMO-1", "The happiness of your life depends upon the quality of your thoughts.", None, "Book Five"),
      ("DEMO-1", "Waste no more time arguing what a good man should be. Be one.", "Demo note: action over debate.", "Book Ten"),
      ("DEMO-2", "Tell me, O Muse, of that ingenious hero.", None, "Book I"),
      ("DEMO-4", "It is a truth universally acknowledged...", None, "Chapter 1")]
for i, (aid, text, note_text, chap) in enumerate(hl):
    ann.execute("INSERT INTO ZAEANNOTATION VALUES (?,0,3,2,?,?,?,?,?,?,?,?)",
                (i + 1, cd(now - datetime.timedelta(days=3 + i)), cd(now - datetime.timedelta(days=3 + i)), aid,
                 f"epubcfi(/6/{10 + i * 2}!/4/2/1:0)", note_text, text, f"DEMO-ANN-{i + 1}", chap))
ann.commit(); ann.close()
print(out)
