"""Classifier adapter. data/tmobile/ is absent, so this is the fallback TF-IDF + LogisticRegression (source="fallback").
See CLASSIFIER_NOTES.md. predict(text) -> {category_id, label, prob} where prob = P(scam) = 1 - P(legit)."""
import pathlib
import joblib
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import FeatureUnion, Pipeline
from .bootstrap_data import CAT_LABELS, LEGIT
from .common import norm

MODEL = pathlib.Path(__file__).parent / "models" / "classifier.joblib"
SOURCE = "fallback"


def thread_text(req) -> str:
    return "\n".join(m.text for m in req.messages[-6:] if m.direction == "in") or req.messages[-1].text


def make_pipeline():
    return Pipeline([("tf", FeatureUnion([("w", TfidfVectorizer(preprocessor=norm, ngram_range=(1, 2), min_df=2, sublinear_tf=True)),
                                          ("c", TfidfVectorizer(preprocessor=norm, analyzer="char_wb", ngram_range=(3, 5), min_df=3, sublinear_tf=True))])),
                     ("lr", LogisticRegression(C=8, max_iter=400))])


def train(texts, cats, save=True):
    p = make_pipeline().fit(texts, cats)
    if save:
        MODEL.parent.mkdir(exist_ok=True)
        joblib.dump(p, MODEL)
    return p


class Classifier:
    def __init__(self, pipe):
        self.pipe = pipe
        self.legit_i = list(pipe.classes_).index(LEGIT)

    def predict(self, text: str) -> dict:
        pr = self.pipe.predict_proba([text])[0]
        scam = [(p, c) for p, c in zip(pr, self.pipe.classes_) if c != LEGIT]
        p_cat, cat = max(scam)
        return dict(category_id=cat if 1 - pr[self.legit_i] >= 0.5 else LEGIT, label=CAT_LABELS.get(cat, cat), prob=float(1 - pr[self.legit_i]))
