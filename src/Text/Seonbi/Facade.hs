{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}
-- | Provides higher-level APIs.  Read 'transformHtmlText' function first,
-- and then see also 'Configuration' type.
module Text.Seonbi.Facade
    ( ArrowOption (..)
    , CiteOption (..)
    , Configuration (..)
    , HanjaDictionary
    , HanjaOption (..)
    , HanjaReadingOption (..)
    , HanjaRenderingOption (..)
    , QuoteOption (..)
    , transformHtmlText
    , transformHtmlLazyText
    ) where

import Data.Maybe

import Data.Set
import Data.Text
import qualified Data.Text.Lazy as LT

import Text.Seonbi.Hanja
import Text.Seonbi.Html
import Text.Seonbi.Punctuation
import Text.Seonbi.Trie

-- | Transformation settings.
data Monad m => Configuration m a = Configuration 
    { -- | An optional debugging logger to print its internal AST.
      debugLogger :: Maybe (HtmlEntity -> m a)
      -- | An option to decide how quotation marks are rendered.
      -- If 'Nothing' no quotes are transformed.
    , quote :: Maybe QuoteOption
      -- | An option to transform folk-citing quotes (e.g., @\<\<한겨레\>\>@)
      -- into proper citing quotes (e.g., @《한겨레》).
    , cite :: Maybe CiteOption
      -- | Settings to transform arrow-looking punctuations into proper arrows.
      -- If 'Nothing' no arrows are transformed.
    , arrow :: Maybe ArrowOption
      -- | Whether to transform triple periods into a proper ellipsis.
    , ellipsis :: Bool
      -- | Settings to deal with Sino-Korean words.
    , hanja :: Maybe HanjaOption
      -- | Whether to take and result in XHTML instead of HTML.
    , xhtml :: Bool
    }

instance Monad m => Show (Configuration m a) where
    show c = "Configuration {\n" <>
        "  debugLogger = " <>
            maybe "Nothing" (const "Just ...") (debugLogger c) <> "," <>
        "  quote = " <> show (quote c) <> "," <>
        "  arrow = " <> show (cite c) <> "," <>
        "  cite = " <> show (arrow c) <> "," <>
        "  ellipsis = " <> show (ellipsis c) <> "," <>
        "  hanja = " <> show (hanja c) <> "," <>
        "  xhtml = " <> show (xhtml c) <>
        "}"

-- | An option to decide how quotation marks are rendered.
data QuoteOption
    -- | English-style curved quotes (@‘@: U+2018, @’@: U+2019, @“@: U+201C,
    -- @”@: U+201D), which are used by South Korean orthography.
    = CurvedQuotes
    -- | East Asian guillemets (@〈@: U+3008, @〉@: U+3009, @《@: U+300A, @》@:
    -- U+300B), which are used by North Korean orthography.
    | Guillemets 
    -- | Use English-style curved quotes (@‘@: U+2018, @’@: U+2019) for single
    -- quotes, and HTML @\<q\>@ tags for double quotes.
    | CurvedSingleQuotesWithQ 
    deriving (Enum, Eq, Read, Show)

-- | An option to transform folk-citing quotes (e.g., @\<\<한겨레\>\>@) into
-- proper citing quotes (e.g., @《한겨레》).
data CiteOption
    -- | Cite a title using angle quotes, used by South Korean orthography in
    -- horizontal writing (橫書), e.g., 《나비와 엉겅퀴》 or 〈枾崎의 바다〉.
    = AngleQuotes
    -- | Cite a title using corner brackets, used by South Korean orthography in
    -- vertical writing (縱書) and Japanese orthography,
    -- e.g., 『나비와 엉겅퀴』 or 「枾崎의 바다」.
    | CornerBrackets
    -- | Same as 'AngleQuotes' except it wraps the title with a @\<cite\>@ tag.
    | AngleQuotesWithCite
    -- | Same as 'CornerBrackets' except it wraps the title with
    -- a @\<cite\>@ tag.
    | CornerBracketsWithCite
    deriving (Enum, Eq, Read, Show)

-- | Settings to transform arrow-looking punctuations into proper arrows.
data ArrowOption = ArrowOption
    { -- | Whether to transform bi-directional arrows as well as
      -- left/rightwards arrows.
      bidirArrow :: Bool
      -- | Whether to transform double arrows as well as single arrows.
    , doubleArrow :: Bool
    } deriving (Eq, Show)

-- | Settings to deal with Sino-Korean words.
data HanjaOption = HanjaOption
    { -- | How to render Sino-Korean words.
      rendering :: HanjaRenderingOption
      -- | How to rewrite Sino-Korean words in hangul.
    , reading :: HanjaReadingOption
    } deriving (Eq, Show)

-- | Available options to render Sino-Korean words.
data HanjaRenderingOption
    -- | Renders a word in hangul-only, no hanja at all (e.g., @안녕히@).
    = HangulOnly
    -- | Renders a word in hangul followed by hanja in parentheses
    -- (e.g., @안녕(安寧)히@).
    | HanjaInParentheses
    -- | Renders words in hangul-only for the most part, and if there are
    -- homophones in a document put their hanja notation in parentheses
    -- (e.g., @안녕히@ or @소수(小數)와 소수(素數)@).
    | DisambiguatingHanjaInParentheses
    -- | Renders a word in @<ruby>@ tag (e.g.,
    -- @\<ruby\>安寧\<rp\>(\<\/rp\>\<rt\>안녕\<\/rt\>\<rp\>)\<\/rp\>\<\/ruby\>히@).
    --
    -- Please read [Use Cases & Exploratory Approaches for Ruby
    -- Markup](https://www.w3.org/TR/ruby-use-cases/) as well for more
    -- information.
    | HanjaInRuby
    deriving (Enum, Eq, Read, Show)

-- | Settings to read Sino-Korean words.
data HanjaReadingOption = HanjaReadingOption
    { -- | A dictionary which has hanja readings.  Keys are
      -- hanja words and values are their corresponding hangul readings,
      -- e.g.:
      --
      -- > [("敗北", "패배"), ("北極", "북극")] :: HanjaDictionary
      dictionary :: HanjaDictionary
      -- | Whether to apply Initial Sound Law (頭音法則) or not.
    , initialSoundLaw :: Bool
    } deriving (Eq, Show)

-- | Transforms a given HTML text.  'Nothing' if it fails to parse the given
-- HTML text.
transformHtmlText :: Monad m => Configuration m a -> Text -> m Text
transformHtmlText config =
    fmap LT.toStrict . transformHtmlLazyText config . LT.fromStrict

-- | A lazy version of 'transformHtmlText' function.
transformHtmlLazyText :: Monad m => Configuration m a -> LT.Text -> m LT.Text
transformHtmlLazyText config@Configuration { xhtml, debugLogger } htmlText =
    case scanHtml htmlText of
        Done "" input -> do
            case debugLogger of
                Just logger -> mapM_ logger input
                Nothing -> return ()
            return $ printHtml' $ toTransformer config input
        _ ->
            fail "failed to parse input"
  where
    printHtml' :: [HtmlEntity] -> LT.Text
    printHtml'
      | xhtml = printXhtml
      | otherwise = printHtml

toTransformers :: Monad m => Configuration m a -> [[HtmlEntity] -> [HtmlEntity]]
toTransformers Configuration { quote, cite, arrow, ellipsis, hanja } =
    [ case quote of
        Nothing -> id
        Just quoteOption -> transformQuote $
            case quoteOption of
                CurvedQuotes -> curvedQuotes
                Guillemets -> guillemets
                CurvedSingleQuotesWithQ -> curvedSingleQuotesWithQ
    , case cite of
        Nothing -> id
        Just citeOption -> quoteCitation $
            case citeOption of
                AngleQuotes -> angleQuotes { htmlElement = Nothing }
                CornerBrackets -> cornerBrackets { htmlElement = Nothing }
                AngleQuotesWithCite -> angleQuotes
                CornerBracketsWithCite -> cornerBrackets
    , case arrow of
        Nothing -> id
        Just ArrowOption { bidirArrow, doubleArrow } -> transformArrow $
            Data.Set.fromList $ catMaybes
                [ if bidirArrow then Just LeftRight else Nothing
                , if doubleArrow then Just DoubleArrow else Nothing
                ]
    , if ellipsis then transformEllipsis else id
    , case hanja of
        Nothing ->
            id
        Just HanjaOption
                { rendering
                , reading = HanjaReadingOption { initialSoundLaw, dictionary }
                } ->
            phoneticizeHanja $ def
                { phoneticizer =
                    let withDict = if Text.Seonbi.Trie.null dictionary
                            then withDictionary dictionary
                            else id
                        phoneticize = if initialSoundLaw
                            then phoneticizeHanjaWordWithInitialSoundLaw
                            else phoneticizeHanjaWord
                    in
                        withDict phoneticize
                , wordRenderer = case rendering of
                    HangulOnly -> hangulOnly
                    HanjaInParentheses -> hanjaInParentheses
                    DisambiguatingHanjaInParentheses -> hangulOnly
                    HanjaInRuby -> hanjaInRuby
                , homophoneRenderer = case rendering of
                    HangulOnly -> hangulOnly
                    HanjaInParentheses -> hanjaInParentheses
                    DisambiguatingHanjaInParentheses -> hanjaInParentheses
                    HanjaInRuby -> hanjaInRuby
                }
    ]

toTransformer :: Monad m => Configuration m a -> [HtmlEntity] -> [HtmlEntity]
toTransformer =
    Prelude.foldl (.) id . toTransformers