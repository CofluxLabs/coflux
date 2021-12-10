import requests
import datetime as dt
import typing as t
import nltk
import collections

from bs4 import BeautifulSoup
from coflux import step, task

# TODO
USER_AGENT = 'Mozilla/5.0 (X11; Linux x86_64; rv:94.0) Gecko/20100101 Firefox/94.0'


nltk.download('punkt')


def _wiki_get(url):
    r = requests.get(url, headers={'User-Agent': USER_AGENT})
    r.raise_for_status()
    return r


@step()
def top_pages(date):
    date = dt.date.fromisoformat(date.result())
    url = f'https://wikimedia.org/api/rest_v1/metrics/pageviews/top/en.wikipedia/all-access/{date.year}/{date.month:02d}/{date.day:02d}'
    return _wiki_get(url).json()['items'][0]['articles']


@step()
def fetch_article_metadata(name: str):
    return _wiki_get(f'https://en.wikipedia.org/api/rest_v1/page/title/{name.result()}').json()['items'][0]


@step(cache_key_fn=lambda name, revision: f"wikipedia:{name}:{revision}")
def fetch_article_content(name: str, revision: int):
    return _wiki_get(f'https://en.wikipedia.org/api/rest_v1/page/html/{name.result()}/{revision.result()}').text


@step()
def convert_to_text(html: str):
    soup = BeautifulSoup(html.result(), 'html.parser')
    return soup.get_text()


@step()
def tokenise(text: str):
    return nltk.word_tokenize(text.result())


@step()
def count_tokens(tokens: t.List[str]):
    return collections.Counter(tokens.result()).most_common(100)


@step()
def process_article(name: str):
    name = name.result()
    metadata = fetch_article_metadata(name).result()
    content = fetch_article_content(name, metadata['rev'])
    return count_tokens(tokenise(convert_to_text(content)))


@task()
def wikipedia_task(date: t.Optional[str] = None, n: int = 3):
    date = date.result() or (dt.datetime.now(dt.timezone.utc).date() - dt.timedelta(days=1)).isoformat()
    article_names = [a['article'] for a in top_pages(date).result()]
    article_names = [a for a in article_names if not a.startswith('Special:') and a != 'Main_Page']
    for article_name in article_names[: n.result()]:
        process_article(article_name)
