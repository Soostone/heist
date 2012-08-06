{-# LANGUAGE BangPatterns               #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE NoMonomorphismRestriction  #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE TypeSynonymInstances       #-}

module Caper where
--   (
--     -- * Types
--     Template
--   , MIMEType
--   , CaperSplice
--   , HeistT
--   , HeistState
--   , evalHeistT
--   , templateNames
--   , spliceNames
-- 
--     -- * Functions and declarations on HeistState values
--   , addTemplate
--   , addXMLTemplate
--   , defaultHeistState
--   , bindSplice
--   , bindSplices
--   , lookupCaperSplice
--   , setTemplates
--   , loadTemplates
--   , hasTemplate
--   , addTemplatePathPrefix
-- 
--     -- * Hook functions
--     -- $hookDoc
--   , addOnLoadHook
--   , addPreRunHook
--   , addPostRunHook
-- 
--     -- * HeistT functions
--   , stopRecursion
--   , getParamNode
--   , runNodeList
--   , getContext
--   , getTemplateFilePath
-- 
--   , localParamNode
--   , getsTS
--   , getTS
--   , putTS
--   , modifyTS
--   , restoreTS
--   , localTS
-- 
--     -- * Functions for running splices and templates
--  , evalTemplate
--  , callTemplate
--  , callTemplateWithText
--  , renderTemplate
--  , renderWithArgs
--  , bindStrings
--  , bindString
--
--    -- * Functions for creating splices
--  , textSplice
--  , runChildren
--  , runChildrenWith
--  , runChildrenWithTrans
--  , runChildrenWithTemplates
--  , runChildrenWithText
--  , mapSplices
--
--    -- * Misc functions
--  , getDoc
--  , getXMLDoc
--  , mkCacheTag
--  ) where

import           Blaze.ByteString.Builder
import           Blaze.ByteString.Builder.ByteString
import           Control.Applicative
import           Control.Arrow
import           Control.Exception
import           Control.Monad.RWS.Strict
import           Control.Monad.State.Strict
import qualified Data.Attoparsec.Text            as AP
import           Data.ByteString.Char8           (ByteString)
import qualified Data.ByteString.Char8           as S
import qualified Data.ByteString.Lazy.Char8      as L
import           Data.DList                      (DList)
import qualified Data.DList                      as DL
import           Data.Either
import qualified Data.Foldable                   as F
import           Data.HashMap.Strict             (HashMap)
import qualified Data.HashMap.Strict             as H
import           Data.HeterogeneousEnvironment   (HeterogeneousEnvironment)
import qualified Data.HeterogeneousEnvironment   as HE
import           Data.List                       (foldl', isSuffixOf)
import           Data.Maybe
import           Data.String
import           Data.Text                       (Text)
import qualified Data.Text                       as T
import qualified Data.Text.Encoding              as T
import qualified Data.Text.Lazy                  as LT
import qualified Data.Vector                     as V
import           Prelude                         hiding (catch)
import           System.Directory.Tree           hiding (name)
import           System.FilePath
import           Text.Blaze.Html
import qualified Text.Blaze.Html                 as Blaze
import           Text.Blaze.Internal
import qualified Text.Blaze.Html.Renderer.String as BlazeString
import qualified Text.Blaze.Html.Renderer.Text   as BlazeText
import           Text.Blaze.Html.Renderer.Utf8
import           Text.Templating.Heist.Common
import           Text.Templating.Heist.Types
import qualified Text.XmlHtml                    as X

import Debug.Trace

-- $hookDoc
-- Heist hooks allow you to modify templates when they are loaded and before
-- and after they are run.  Every time you call one of the addAbcHook
-- functions the hook is added to onto the processing pipeline.  The hooks
-- processes the template in the order that they were added to the
-- HeistState.
--
-- The pre-run and post-run hooks are run before and after every template is
-- run/rendered.  You should be careful what code you put in these hooks
-- because it can significantly affect the performance of your site.

{-

dlistRunNode :: Monad m
             => X.Node
             -> HeistT (Output m1) m (Output m1)
dlistRunNode (X.Element nm attrs ch) = do
    -- Parse the attributes: we have Left for static and Right for runtime
    -- TODO: decide: do we also want substitution in the key?
    compiledAttrs <- mapM attSubst attrs
    childHtml <- runNodeList ch
    return $ DL.concat [ DL.singleton $ Pure tag0
                       , DL.concat $ map renderAttr compiledAttrs
                       , DL.singleton $ Pure ">"
                       , childHtml
                       , DL.singleton $ Pure end
                       ]
  where
    tag0 = T.append "<" nm
    end = T.concat [ "</" , nm , ">"]
    renderAttr (n,v) = DL.concat [ DL.singleton $ Pure $ T.append " " n
                                 , DL.singleton $ Pure "="
                                 , v ]
dlistRunNode (X.TextNode t) = return $ textSplice t
dlistRunNode (X.Comment t) = return $ textSplice t



------------------------------------------------------------------------------
-- | Renders a template with the specified arguments passed to it.  This is a
-- convenience function for the common pattern of calling renderTemplate after
-- using bindString, bindStrings, or bindSplice to set up the arguments to the
-- template.
renderWithArgs :: Monad m
               => [(Text, Text)]
               -> HeistState (Output m) m
               -> ByteString
               -> m (Maybe (Builder, MIMEType))
renderWithArgs args ts = renderTemplate (bindStrings args ts)


------------------------------------------------------------------------------
-- | Renders a template from the specified HeistState to a 'Builder'.  The
-- MIME type returned is based on the detected character encoding, and whether
-- the root template was an HTML or XML format template.  It will always be
-- @text/html@ or @text/xml@.  If a more specific MIME type is needed for a
-- particular XML application, it must be provided by the application.
renderTemplate :: Monad m
               => HeistState (Output m) m
               -> ByteString
               -> m (Maybe (Builder, MIMEType))
renderTemplate ts name = evalHeistT tpl (X.TextNode "") ts
  where
    tpl = lookupAndRun name $ \(t,ctx) -> do
        addDoctype $ maybeToList $ X.docType $ cdfDoc t
        localTS (\ts' -> ts' {_curContext = ctx}) $ do
            res <- runNodeList $ X.docContent $ cdfDoc t
            return $ Just (res, mimeType $ cdfDoc t)

-}

------------------------------------------------------------------------------
------------------------------------------------------------------------------
------------------------------------------------------------------------------

------------------------------------------------------------------------------
runNodeList :: (Monad m) => Template -> CaperSplice n m
runNodeList nodes = liftM DL.concat $ mapM runNode nodes


------------------------------------------------------------------------------
lookupCompiledTemplate :: ByteString
                       -> CompiledTemplateMap m
                       -> Maybe (m Builder)
lookupCompiledTemplate nm (CompiledTemplateMap m) = H.lookup nm m


------------------------------------------------------------------------------
runSplice :: (Monad n)
          => X.Node
          -> HeistState n IO
          -> CaperSplice n IO
          -> IO (n Builder)
runSplice node hs splice = do
    (!a,_) <- runHeistT splice node hs
    return $! (flip evalStateT HE.empty $! unRT $! codeGen a)


------------------------------------------------------------------------------
runDocumentFile :: (Monad m)
                => TPath
                -> DocumentFile
                -> CaperSplice n m
runDocumentFile tpath df = do
    modifyTS (setCurTemplateFile curPath .  setCurContext tpath)
    runNodeList nodes
  where
    curPath     = dfFile df
    nodes       = X.docContent $ dfDoc df


------------------------------------------------------------------------------
compileTemplate :: Monad n
                => HeistState n IO
                -> TPath
                -> DocumentFile
                -> IO (n Builder)
compileTemplate ss tpath df = do
    runSplice nullNode ss $ runDocumentFile tpath df
  where
    -- This gets overwritten in runDocumentFile
    nullNode = X.TextNode ""


------------------------------------------------------------------------------
compileTemplates :: Monad n => HeistState n IO -> IO (CompiledTemplateMap n)
compileTemplates hs =
    liftM CompiledTemplateMap $ foldM runOne H.empty tpathDocfiles
  where
    tpathDocfiles :: [(TPath, ByteString, DocumentFile)]
    tpathDocfiles = map (\(a,b) -> (a, tpathToPath a, b))
                        (H.toList $ _templateMap hs)

    tpathToPath tp = S.intercalate "/" $ reverse tp

    runOne tmap (tpath, nm, df) = do
        mHtml <- compileTemplate hs tpath df
        return $! H.insert nm mHtml tmap


------------------------------------------------------------------------------
-- | Given a list of output chunks, consolidate turns consecutive runs of
-- @Pure Html@ values into maximally-efficient pre-rendered strict
-- 'ByteString' chunks.
codeGen :: Monad m => DList (Chunk m) -> RuntimeSplice m Builder
codeGen = compileConsolidated . consolidate . DL.toList
  where
    consolidate :: (Monad m) => [Chunk m] -> [Chunk m]
    consolidate []     = []
    consolidate (y:ys) = boilDown [] $! go [] y ys
      where
        ----------------------------------------------------------------------
        go soFar x [] = x : soFar

        go soFar (Pure a) ((Pure b) : xs) =
            go soFar (Pure $! a `mappend` b) xs

        go soFar (RuntimeHtml a) ((RuntimeHtml b) : xs) =
            go soFar (RuntimeHtml $! a `mappend` b) xs

        go soFar (RuntimeHtml a) ((RuntimeAction b) : xs) =
            go soFar (RuntimeHtml $! a >>= \x -> b >> return x) xs

        go soFar (RuntimeAction a) ((RuntimeHtml b) : xs) =
            go soFar (RuntimeHtml $! a >> b) xs

        go soFar (RuntimeAction a) ((RuntimeAction b) : xs) =
            go soFar (RuntimeAction $! a >> b) xs

        go soFar a (b : xs) = go (a : soFar) b xs

        ----------------------------------------------------------------------
        -- FIXME Why isn't this used?
        --render h = unsafeByteString $! S.concat $! L.toChunks $! renderHtml h

        ----------------------------------------------------------------------
        boilDown soFar []              = soFar

        boilDown soFar ((Pure h) : xs) = boilDown ((Pure $! h) : soFar) xs

        boilDown soFar (x : xs) = boilDown (x : soFar) xs


    --------------------------------------------------------------------------
    compileConsolidated :: (Monad m) => [Chunk m] -> RuntimeSplice m Builder
    compileConsolidated l = V.foldr mappend mempty v
      where
        toAct (RuntimeHtml m)   = liftM (fromByteString . T.encodeUtf8) m
        toAct (Pure h)          = return $ fromByteString $ T.encodeUtf8 h
        toAct (RuntimeAction m) = m >> return mempty

        !v = V.map toAct $! V.fromList l
    {-# INLINE compileConsolidated #-}
{-# INLINE codeGen #-}


------------------------------------------------------------------------------
yieldChunk :: Monad m => a -> m (DList a)
yieldChunk = return . DL.singleton
{-# INLINE yieldChunk #-}


------------------------------------------------------------------------------
yield :: (Monad m) => Text -> CaperSplice n m
yield = yieldChunk . Pure
{-# INLINE yield #-}


------------------------------------------------------------------------------
yieldRuntimeSplice :: (Monad m) => RuntimeSplice n () -> CaperSplice n m
yieldRuntimeSplice = yieldChunk . RuntimeAction
{-# INLINE yieldRuntimeSplice #-}


------------------------------------------------------------------------------
yieldRuntimeHtml :: (Monad m) => RuntimeSplice n Text -> CaperSplice n m
yieldRuntimeHtml = yieldChunk . RuntimeHtml
{-# INLINE yieldRuntimeHtml #-}


------------------------------------------------------------------------------
yieldLater :: (Monad n, Monad m) => n Text -> CaperSplice n m
yieldLater = yieldRuntimeHtml . RuntimeSplice . lift
{-# INLINE yieldLater #-}


------------------------------------------------------------------------------
yieldPromise :: (Monad m, Monad n) => Promise Text -> CaperSplice n m
yieldPromise p = yieldRuntimeHtml $ getPromise p
{-# INLINE yieldPromise #-}


------------------------------------------------------------------------------
lookupCaperSplice :: Monad m => Text -> HeistT n m (Maybe (CaperSplice n m))
lookupCaperSplice nm = getsTS (H.lookup nm . _caperSpliceMap)


------------------------------------------------------------------------------
runNode :: (Monad m) => X.Node -> CaperSplice n m
runNode node = localParamNode (const node) $ do
    isStatic <- subtreeIsStatic node
    if isStatic
      then yield $! T.decodeUtf8
                 $! toByteString
                 $! X.renderHtmlFragment X.UTF8 [node]
      else compileNode node


------------------------------------------------------------------------------
subtreeIsStatic :: Monad m => X.Node -> HeistT n m Bool
subtreeIsStatic (X.Element nm attrs ch) = do
    isNodeDynamic <- liftM isJust $ lookupCaperSplice nm
    if isNodeDynamic
      then return False
      else do
          let hasDynamicAttrs = any hasSubstitutions attrs
          if hasDynamicAttrs
            then return False
            else do
                staticSubtrees <- mapM subtreeIsStatic ch
                return $ and staticSubtrees
  where
    hasSubstitutions (k,v) = hasAttributeSubstitutions k ||
                             hasAttributeSubstitutions v

subtreeIsStatic _ = return True


------------------------------------------------------------------------------
hasAttributeSubstitutions :: Text -> Bool
hasAttributeSubstitutions txt = all isLiteral ast
  where
    ast = case AP.feed (AP.parse attParser txt) "" of
            (AP.Done _ res) -> res
            (AP.Fail _ _ _) -> []
            (AP.Partial _ ) -> []


------------------------------------------------------------------------------
-- | Given a 'X.Node' in the DOM tree, produces a \"runtime splice\" that will
-- generate html at runtime. Leaves the writer monad state untouched.
compileNode :: (Monad m) => X.Node -> CaperSplice n m
compileNode (X.Element nm attrs ch) =
    -- Is this node a splice, or does it merely contain splices?
    lookupCaperSplice nm >>= fromMaybe compileStaticElement
  where
    tag0 = T.append "<" nm
    end = T.concat [ "</" , nm , ">"]
    -- If the tag is not a splice, but it contains dynamic children
    compileStaticElement = do
        -- Parse the attributes: we have Left for static and Right for runtime
        -- TODO: decide: do we also want substitution in the key?
        compiledAttrs <- mapM parseAtt attrs

        childHtml <- runNodeList ch

        return $ DL.concat [ DL.singleton $ Pure tag0
                           , DL.concat compiledAttrs
                           , DL.singleton $ Pure ">"
                           , childHtml
                           , DL.singleton $ Pure end
                           ]
compileNode _ = error "impossible"


------------------------------------------------------------------------------
-- | If this function returns a 'Nothing', there are no dynamic splices in the
-- attribute text, and you can just spit out the text value statically.
-- Otherwise, the splice has to be resolved at runtime.
parseAtt :: Monad m => (Text, Text) -> HeistT n m (DList (Chunk n))
parseAtt (k,v) = do
    let ast = case AP.feed (AP.parse attParser v) "" of
                (AP.Done _ res) -> res
                (AP.Fail _ _ _) -> []
                (AP.Partial _ ) -> []
    chunks <- mapM cvt ast
    let value = DL.concat chunks
    return $ DL.concat [ DL.singleton $ Pure $ T.concat [" ", k, "=\""]
                       , value, DL.singleton $ Pure "\"" ]
  where
    cvt (Literal x) = return $ DL.singleton $ Pure x
    cvt (Ident x) =
        localParamNode (const $ X.Element x [] []) $ getAttributeSplice x


------------------------------------------------------------------------------
getAttributeSplice :: Monad m => Text -> HeistT n m (DList (Chunk n))
getAttributeSplice name =
    lookupCaperSplice name >>= fromMaybe (return DL.empty)
{-# INLINE getAttributeSplice #-}


------------------------------------------------------------------------------
getPromise :: (Monad m) => Promise a -> RuntimeSplice m a
getPromise (Promise k) = do
    mb <- gets (HE.lookup k)
    return $ fromMaybe err mb

  where
    err = error $ "getPromise: dereferenced empty key (id "
                  ++ show (HE.getKeyId k) ++ ")"
{-# INLINE getPromise #-}


------------------------------------------------------------------------------
putPromise :: (Monad m) => Promise a -> a -> RuntimeSplice m ()
putPromise (Promise k) x = modify (HE.insert k x)
{-# INLINE putPromise #-}


------------------------------------------------------------------------------
adjustPromise :: Monad m => Promise a -> (a -> a) -> RuntimeSplice m ()
adjustPromise (Promise k) f = modify (HE.adjust f k)
{-# INLINE adjustPromise #-}


------------------------------------------------------------------------------
newEmptyPromise :: MonadIO m => HeistT n m (Promise a)
newEmptyPromise = do
    keygen <- getsTS _keygen
    key    <- liftIO $ HE.makeKey keygen
    return $! Promise key
{-# INLINE newEmptyPromise #-}


------------------------------------------------------------------------------
newEmptyPromiseWithError :: (Monad n, MonadIO m)
                         => String -> HeistT n m (Promise a)
newEmptyPromiseWithError from = do
    keygen <- getsTS _keygen
    prom   <- liftM Promise $ liftIO $ HE.makeKey keygen

    yieldRuntimeSplice $ putPromise prom
                       $ error
                       $ "deferenced empty promise created at" ++ from

    return prom
{-# INLINE newEmptyPromiseWithError #-}


------------------------------------------------------------------------------
promise :: (Monad n, MonadIO m) => n a -> HeistT n m (Promise a)
promise act = runtimeSplicePromise (lift act)
{-# INLINE promise #-}


------------------------------------------------------------------------------
runtimeSplicePromise :: (Monad n, MonadIO m)
                     => RuntimeSplice n a
                     -> HeistT n m (Promise a)
runtimeSplicePromise act = do
    prom <- newEmptyPromiseWithError "runtimeSplicePromise"

    let m = do
        x <- act
        putPromise prom x
        return ()

    yieldRuntimeSplice m
    return prom
{-# INLINE runtimeSplicePromise #-}


------------------------------------------------------------------------------
withPromise :: (Monad n, MonadIO m)
            => Promise a
            -> (a -> n b)
            -> HeistT n m (Promise b)
withPromise promA f = do
    promB <- newEmptyPromiseWithError "withPromise"

    let m = do
        a <- getPromise promA
        b <- lift $ f a
        putPromise promB b
        return ()

    yieldRuntimeSplice m
    return promB
{-# INLINE withPromise #-}


------------------------------------------------------------------------------
bindCaperSplice :: Text             -- ^ tag name
                -> CaperSplice n m  -- ^ splice action
                -> HeistState n m   -- ^ source state
                -> HeistState n m
bindCaperSplice n v ts =
    ts { _caperSpliceMap = H.insert n v (_caperSpliceMap ts) }


------------------------------------------------------------------------------
bindCaperSplices :: [(Text, CaperSplice n m)]  -- ^ splices to bind
                 -> HeistState n m             -- ^ source state
                 -> HeistState n m
bindCaperSplices ss ts = foldr (uncurry bindCaperSplice) ts ss


------------------------------------------------------------------------------
-- | Converts 'Text' to a splice yielding the text, html-encoded.
textSplice :: Monad m => Text -> CaperSplice n m
textSplice = yield


------------------------------------------------------------------------------
runChildrenCaper :: (Monad m) => CaperSplice n m
runChildrenCaper = getParamNode >>= runNodeList . X.childNodes


------------------------------------------------------------------------------
-- | Binds a list of splices before using the children of the spliced node as
-- a view.
runChildrenWithCaper :: (Monad m)
    => [(Text, CaperSplice n m)]
    -- ^ List of splices to bind before running the param nodes.
    -> CaperSplice n m
    -- ^ Returns the passed in view.
runChildrenWithCaper splices = localTS (bindCaperSplices splices) runChildrenCaper


------------------------------------------------------------------------------
-- | Wrapper around runChildrenWithCaper that applies a transformation function to
-- the second item in each of the tuples before calling runChildrenWithCaper.
runChildrenWithTransCaper :: (Monad m)
    => (b -> CaperSplice n m)
    -- ^ Splice generating function
    -> [(Text, b)]
    -- ^ List of tuples to be bound
    -> CaperSplice n m
runChildrenWithTransCaper f = runChildrenWithCaper . map (second f)


------------------------------------------------------------------------------
runChildrenWithTextCaper :: (Monad m)
                    => [(Text, Text)]
                    -- ^ List of tuples to be bound
                    -> CaperSplice n m
runChildrenWithTextCaper = runChildrenWithTransCaper textSplice


------------------------------------------------------------------------------
-- Above here should be correct
------------------------------------------------------------------------------


-- ------------------------------------------------------------------------------
-- loadTemplate :: FilePath    -- ^ path to the template root
--              -> FilePath    -- ^ full file path (includes template root)
--              -> IO [Either String (TPath, CaperDocumentFile m)]
-- loadTemplate templateRoot fname
--     | isHtmlTemplate = do
--         c <- getDoc fname
--         return $! [fmap (\t -> (splitLocalPath $ S.pack tName, t)) c]
--     | otherwise = return []
-- 
--   where
--     isHtmlTemplate = ".tpl" `isSuffixOf` fname
--     relfile        = makeRelative templateRoot fname
--     tName          = dropExtension relfile
-- 
-- 
-- ------------------------------------------------------------------------------
-- getDoc :: FilePath -> IO (Either String (CaperDocumentFile m))
-- getDoc f = do
--     bs <- catch (liftM Right $ S.readFile f)
--                 (\(e::SomeException) -> return $ Left $ show e)
-- 
--     let eitherDoc = either Left (X.parseHTML f) bs
--     return $ either (\s -> Left $ f ++ " " ++ s)
--                     (\d -> Right $ CaperDocumentFile d (Just f)) eitherDoc
-- 
-- 
-- ------------------------------------------------------------------------------
-- -- | Traverses the specified directory structure and builds a HeistState by
-- -- loading all the files with a ".tpl" extension.
-- --loadTemplates :: Monad m
-- --              => FilePath
-- --              -> HeistState n m
-- --              -> IO (Either String (HeistState n m))
-- loadTemplates dir ts = do
--     d <- readDirectoryWith (loadTemplate dir) dir
--     let tlist = F.fold (free d)
--         errs = lefts tlist
--     case errs of
--         [] -> return $! Right $! foldl' ins ts $ rights tlist
--         _  -> return $ Left $ unlines errs
-- 
--   where
--     ins !ss (tp, t) = insertTemplate tp t ss
-- 
-- 
-- ------------------------------------------------------------------------------
-- -- | Adds a template to the splice state.
-- insertTemplate :: Monad m
--                => TPath
--                -> CaperDocumentFile m
--                -> HeistState n m
--                -> HeistState n m
-- insertTemplate p t st =
--     setTemplates (H.insert p t (_caperTemplateMap st)) st
-- 
-- 
-- ------------------------------------------------------------------------------
-- -- | Sets the templateMap in a HeistState.
-- setTemplates :: HashMap TPath (CaperDocumentFile m)
--              -> HeistState n m
--              -> HeistState n m
-- setTemplates m ts = ts { _caperTemplateMap = m }
-- 
-- 
-- ------------------------------------------------------------------------------
-- --lookupAndRun :: Monad m
-- --             => ByteString
-- --             -> ((CaperDocumentFile, TPath) -> HeistT n m (Maybe a))
-- --             -> HeistT n m (Maybe a)
-- lookupAndRun name k = do
--     ts <- getTS
--     let mt = lookupTemplate name ts _caperTemplateMap
--     maybe (return Nothing)
--           (\dftp -> do
--                let curPath = join $ fmap (cdfFile . fst) mt
--                modifyTS (setCurTemplateFile curPath)
--                k dftp)
--           mt
-- 
-- 
-- ------------------------------------------------------------------------------
-- -- | Gets the current context
-- getContext :: Monad m => HeistT n m TPath
-- getContext = getsTS _curContext
-- 
-- 
-- ------------------------------------------------------------------------------
-- -- | Gets the full path to the file holding the template currently being
-- -- processed.  Returns Nothing if the template is not associated with a file
-- -- on disk or if there is no template being processed.
-- --getTemplateFilePath :: Monad m => HeistT n m (Maybe FilePath)
-- getTemplateFilePath = getsTS _curTemplateFile
-- 
-- 
-- ------------------------------------------------------------------------------
-- {-
-- 
-- Example:
-- 
-- <blog:listRecentPosts>
--   <a href="${post:href}"><post:title/></a>
-- </blog:listRecentPosts>
-- 
-- getRecentPosts :: Int -> Snap [ PostInfo ]
-- getRecentPosts = undefined
-- 
-- 
-- ------------------------------------------------------------------------------
-- foo :: HeistT Snap ()
-- foo = do
--     postListPromise <- promise (getRecentPosts 10)
--     postPromise     <- newEmptyPromise
-- 
--     childTemplate <- localTS $ do
--                          bindSplices [ ("post:title", titleWith postPromise)
--                                      , ("post:href" , hrefWith  postPromise)
--                                      ]
-- 
--                      runChildren
-- 
--     let xxxx = withPromise postListPromise $ \postList -> do
--                    htmls <- mapM (\post -> putPromise postPromise post >> childTemplate) postList
--                    return $! mconcat htmls
-- 
--     yieldLater xxxx
-- 
--   where
--     titleWith p = yieldLater $ withPromise p (return . postTitle)
-- 
-- -}

