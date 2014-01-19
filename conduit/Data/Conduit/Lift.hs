{- | Allow monad transformers to be run/eval/exec in a section of conduit
 rather then needing to run across the whole conduit.
The circumvents many of the problems with breaking the monad transformer laws.
Read more about when the monad transformer laws are broken:
<https://github.com/snoyberg/conduit/wiki/Dealing-with-monad-transformers>

This method has a considerable number of advantages over the other two 
recommended methods.

* Run the monad transformer outisde of the conduit
* Use a mutable varible inside a readerT to retain side effects.

This functionality has existed for awhile in the pipes ecosystem and my recent
improvement to the Pipes.Lift module has allowed it to almost mechanically 
translated for conduit.

-}


module Data.Conduit.Lift (
    -- * ErrorT
    errorC,
    runErrorC,
    catchError,
--    liftCatchError,

    -- * MaybeT
    maybeC,
    runMaybeC,

    -- * ReaderT
    readerC,
    runReaderC,

    -- * StateT
    stateC,
    runStateC,
    evalStateC,
    execStateC,

    -- ** Strict
    stateSC,
    runStateSC,
    evalStateSC,
    execStateSC,

    -- * WriterT
    writerC,
    runWriterC,
    execWriterC,

    -- ** Strict
    writerSC,
    runWriterSC,
    execWriterSC,

    -- * RWST
    rwsC,
    runRWSC,
    evalRWSC,
    execRWSC,

    -- ** Strict
    rwsSC,
    runRWSSC,
    evalRWSSC,
    execRWSSC,

    -- * Utilities

    distribute
    ) where

import Data.Conduit

import Control.Monad.Morph (hoist, lift, MFunctor(..), )
import Control.Monad.Trans.Class (MonadTrans(..))

import Data.Monoid (Monoid(..))


import qualified Control.Monad.Trans.Error as E
import qualified Control.Monad.Trans.Maybe as M
import qualified Control.Monad.Trans.Reader as R

import qualified Control.Monad.Trans.State.Strict as SS
import qualified Control.Monad.Trans.Writer.Strict as WS
import qualified Control.Monad.Trans.RWS.Strict as RWSS

import qualified Control.Monad.Trans.State.Lazy as SL
import qualified Control.Monad.Trans.Writer.Lazy as WL
import qualified Control.Monad.Trans.RWS.Lazy as RWSL


catAwaitLifted
  :: (Monad (t (ConduitM o1 o m)), Monad m, MonadTrans t) =>
     ConduitM i o1 (t (ConduitM o1 o m)) ()
catAwaitLifted = go
  where
    go = do
        x <- lift . lift $ await
        case x of
            Nothing -> return ()
            Just x2 -> do
                yield x2
                go

catYieldLifted
  :: (Monad (t (ConduitM i o1 m)), Monad m, MonadTrans t) =>
     ConduitM o1 o (t (ConduitM i o1 m)) ()
catYieldLifted = go
  where
    go = do
        x <- await
        case x of
            Nothing -> return ()
            Just x2 -> do
                lift . lift $ yield x2
                go


distribute
  :: (Monad (t (ConduitM b o m)), Monad m, Monad (t m), MonadTrans t,
      MFunctor t) =>
     ConduitM b o (t m) () -> t (ConduitM b o m) ()
distribute p = catAwaitLifted =$= hoist (hoist lift) p $$ catYieldLifted

-- | Run 'E.ErrorT' in the base monad
--
-- Since 1.0.11
errorC
  :: (Monad m, Monad (t (E.ErrorT e m)), MonadTrans t, E.Error e,
      MFunctor t) =>
     t m (Either e b) -> t (E.ErrorT e m) b
errorC p = do
    x <- hoist lift p
    lift $ E.ErrorT (return x)

-- | Run 'E.ErrorT' in the base monad
--
-- Since 1.0.11
runErrorC
  :: (Monad m, E.Error e) =>
     ConduitM b o (E.ErrorT e m) () -> ConduitM b o m (Either e ())
runErrorC    = E.runErrorT . distribute
{-# INLINABLE runErrorC #-}

-- | Catch an error in the base monad
--
-- Since 1.0.11
catchError
  :: (Monad m, E.Error e) =>
     ConduitM i o (E.ErrorT e m) ()
     -> (e -> ConduitM i o (E.ErrorT e m) ())
     -> ConduitM i o (E.ErrorT e m) ()
catchError e h = errorC $ E.runErrorT $
    E.catchError (distribute e) (distribute . h)
{-# INLINABLE catchError #-}

-- | Wrap the base monad in 'M.MaybeT'
--
-- Since 1.0.11
maybeC
  :: (Monad m, Monad (t (M.MaybeT m)),
      MonadTrans t,
      MFunctor t) =>
     t m (Maybe b) -> t (M.MaybeT m) b
maybeC p = do
    x <- hoist lift p
    lift $ M.MaybeT (return x)
{-# INLINABLE maybeC #-}

-- | Run 'M.MaybeT' in the base monad
--
-- Since 1.0.11
runMaybeC
  :: Monad m =>
     ConduitM b o (M.MaybeT m) () -> ConduitM b o m (Maybe ())
runMaybeC p = M.runMaybeT $ distribute p
{-# INLINABLE runMaybeC #-}

-- | Wrap the base monad in 'R.ReaderT'
--
-- Since 1.0.11
readerC
  :: (Monad m, Monad (t1 (R.ReaderT t m)),
      MonadTrans t1,
      MFunctor t1) =>
     (t -> t1 m b) -> t1 (R.ReaderT t m) b
readerC k = do
    i <- lift R.ask
    hoist lift (k i)
{-# INLINABLE readerC #-}

-- | Run 'R.ReaderT' in the base monad
--
-- Since 1.0.11
runReaderC
  :: Monad m =>
     r -> ConduitM b o (R.ReaderT r m) () -> ConduitM b o m ()
runReaderC r p = (`R.runReaderT` r) $ distribute p
{-# INLINABLE runReaderC #-}


-- | Wrap the base monad in 'SL.StateT'
--
-- Since 1.0.11
stateC
  :: (Monad m, Monad (t1 (SL.StateT t m)),
      MonadTrans t1,
      MFunctor t1) =>
     (t -> t1 m (b, t)) -> t1 (SL.StateT t m) b
stateC k = do
    s <- lift SL.get
    (r, s') <- hoist lift (k s)
    lift (SL.put s')
    return r
{-# INLINABLE stateC #-}

-- | Run 'SL.StateT' in the base monad
--
-- Since 1.0.11
runStateC
  :: Monad m =>
     s -> ConduitM b o (SL.StateT s m) () -> ConduitM b o m ((), s)
runStateC s p = (`SL.runStateT` s) $ distribute p
{-# INLINABLE runStateC #-}

-- | Evaluate 'SL.StateT' in the base monad
--
-- Since 1.0.11
evalStateC
  :: Monad m =>
     b -> ConduitM b1 o (SL.StateT b m) () -> ConduitM b1 o m ()
evalStateC s p = fmap fst $ runStateC s p
{-# INLINABLE evalStateC #-}

-- | Execute 'SL.StateT' in the base monad
--
-- Since 1.0.11
execStateC
  :: Monad m =>
     b -> ConduitM b1 o (SL.StateT b m) () -> ConduitM b1 o m b
execStateC s p = fmap snd $ runStateC s p
{-# INLINABLE execStateC #-}


-- | Wrap the base monad in 'SS.StateT'
--
-- Since 1.0.11
stateSC
  :: (Monad m, Monad (t1 (SS.StateT t m)),
      MonadTrans t1,
      MFunctor t1) =>
     (t -> t1 m (b, t)) -> t1 (SS.StateT t m) b
stateSC k = do
    s <- lift SS.get
    (r, s') <- hoist lift (k s)
    lift (SS.put s')
    return r
{-# INLINABLE stateSC #-}

-- | Run 'SS.StateT' in the base monad
--
-- Since 1.0.11
runStateSC
  :: Monad m =>
     s -> ConduitM b o (SS.StateT s m) () -> ConduitM b o m ((), s)
runStateSC s p = (`SS.runStateT` s) $ distribute p
{-# INLINABLE runStateSC #-}

-- | Evaluate 'SS.StateT' in the base monad
--
-- Since 1.0.11
evalStateSC
  :: Monad m =>
     b -> ConduitM b1 o (SS.StateT b m) () -> ConduitM b1 o m ()
evalStateSC s p = fmap fst $ runStateSC s p
{-# INLINABLE evalStateSC #-}

-- | Execute 'SS.StateT' in the base monad
--
-- Since 1.0.11
execStateSC
  :: Monad m =>
     b -> ConduitM b1 o (SS.StateT b m) () -> ConduitM b1 o m b
execStateSC s p = fmap snd $ runStateSC s p
{-# INLINABLE execStateSC #-}


-- | Wrap the base monad in 'WL.WriterT'
--
-- Since 1.0.11
writerC
  :: (Monad m, Monad (t (WL.WriterT w m)), MonadTrans t, Monoid w,
      MFunctor t) =>
     t m (b, w) -> t (WL.WriterT w m) b
writerC p = do
    (r, w) <- hoist lift p
    lift $ WL.tell w
    return r
{-# INLINABLE writerC #-}

-- | Run 'WL.WriterT' in the base monad
--
-- Since 1.0.11
runWriterC
  :: (Monad m, Monoid w) =>
     ConduitM b o (WL.WriterT w m) () -> ConduitM b o m ((), w)
runWriterC p = WL.runWriterT $ distribute p
{-# INLINABLE runWriterC #-}

-- | Execute 'WL.WriterT' in the base monad
--
-- Since 1.0.11
execWriterC
  :: (Monad m, Monoid b) =>
     ConduitM b1 o (WL.WriterT b m) () -> ConduitM b1 o m b
execWriterC p = fmap snd $ runWriterC p
{-# INLINABLE execWriterC #-}


-- | Wrap the base monad in 'WS.WriterT'
--
-- Since 1.0.11
writerSC
  :: (Monad m, Monad (t (WS.WriterT w m)), MonadTrans t, Monoid w,
      MFunctor t) =>
     t m (b, w) -> t (WS.WriterT w m) b
writerSC p = do
    (r, w) <- hoist lift p
    lift $ WS.tell w
    return r
{-# INLINABLE writerSC #-}

-- | Run 'WS.WriterT' in the base monad
--
-- Since 1.0.11
runWriterSC
  :: (Monad m, Monoid w) =>
     ConduitM b o (WS.WriterT w m) () -> ConduitM b o m ((), w)
runWriterSC p = WS.runWriterT $ distribute p
{-# INLINABLE runWriterSC #-}

-- | Execute 'WS.WriterT' in the base monad
--
-- Since 1.0.11
execWriterSC
  :: (Monad m, Monoid b) =>
     ConduitM b1 o (WS.WriterT b m) () -> ConduitM b1 o m b
execWriterSC p = fmap snd $ runWriterSC p
{-# INLINABLE execWriterSC #-}


-- | Wrap the base monad in 'RWSL.RWST'
--
-- Since 1.0.11
rwsC
  :: (Monad m, Monad (t1 (RWSL.RWST t w t2 m)), MonadTrans t1,
      Monoid w, MFunctor t1) =>
     (t -> t2 -> t1 m (b, t2, w)) -> t1 (RWSL.RWST t w t2 m) b
rwsC k = do
    i <- lift RWSL.ask
    s <- lift RWSL.get
    (r, s', w) <- hoist lift (k i s)
    lift $ do
        RWSL.put s'
        RWSL.tell w
    return r
{-# INLINABLE rwsC #-}

-- | Run 'RWSL.RWST' in the base monad
--
-- Since 1.0.11
runRWSC
  :: (Monad m, Monoid w) =>
     r
     -> s
     -> ConduitM b o (RWSL.RWST r w s m) ()
     -> ConduitM b o m ((), s, w)
runRWSC  i s p = (\b -> RWSL.runRWST b i s) $ distribute p
{-# INLINABLE runRWSC #-}

-- | Evaluate 'RWSL.RWST' in the base monad
--
-- Since 1.0.11
evalRWSC
  :: (Monad m, Monoid t1) =>
     r
     -> t
     -> ConduitM b o (RWSL.RWST r t1 t m) ()
     -> ConduitM b o m ((), t1)
evalRWSC i s p = fmap f $ runRWSC i s p
  where f x = let (r, _, w) = x in (r, w)
{-# INLINABLE evalRWSC #-}

-- | Execute 'RWSL.RWST' in the base monad
--
-- Since 1.0.11
execRWSC
  :: (Monad m, Monoid t1) =>
     r
     -> t
     -> ConduitM b o (RWSL.RWST r t1 t m) ()
     -> ConduitM b o m (t, t1)
execRWSC i s p = fmap f $ runRWSC i s p
  where f x = let (_, s2, w2) = x in (s2, w2)
{-# INLINABLE execRWSC #-}


-- | Wrap the base monad in 'RWSS.RWST'
--
-- Since 1.0.11
rwsSC
  :: (Monad m, Monad (t1 (RWSS.RWST t w t2 m)), MonadTrans t1,
      Monoid w, MFunctor t1) =>
     (t -> t2 -> t1 m (b, t2, w)) -> t1 (RWSS.RWST t w t2 m) b
rwsSC k = do
    i <- lift RWSS.ask
    s <- lift RWSS.get
    (r, s', w) <- hoist lift (k i s)
    lift $ do
        RWSS.put s'
        RWSS.tell w
    return r
{-# INLINABLE rwsSC #-}

-- | Run 'RWSS.RWST' in the base monad
--
-- Since 1.0.11
runRWSSC
  :: (Monad m, Monoid w) =>
     r
     -> s
     -> ConduitM b o (RWSS.RWST r w s m) ()
     -> ConduitM b o m ((), s, w)
runRWSSC  i s p = (\b -> RWSS.runRWST b i s) $ distribute p
{-# INLINABLE runRWSSC #-}

-- | Evaluate 'RWSS.RWST' in the base monad
--
-- Since 1.0.11
evalRWSSC
  :: (Monad m, Monoid t1) =>
     r
     -> t
     -> ConduitM b o (RWSS.RWST r t1 t m) ()
     -> ConduitM b o m ((), t1)
evalRWSSC i s p = fmap f $ runRWSSC i s p
  where f x = let (r, _, w) = x in (r, w)
{-# INLINABLE evalRWSSC #-}

-- | Execute 'RWSS.RWST' in the base monad
--
-- Since 1.0.11
execRWSSC
  :: (Monad m, Monoid t1) =>
     r
     -> t
     -> ConduitM b o (RWSS.RWST r t1 t m) ()
     -> ConduitM b o m (t, t1)
execRWSSC i s p = fmap f $ runRWSSC i s p
  where f x = let (_, s2, w2) = x in (s2, w2)
{-# INLINABLE execRWSSC #-}

