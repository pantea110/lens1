{-# LANGUAGE CPP #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE PatternGuards #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
#ifdef TRUSTWORTHY
{-# LANGUAGE Trustworthy #-}
#endif
-----------------------------------------------------------------------------
-- |
-- Module      :  Control.Lens.Internal.Deque
-- Copyright   :  (C) 2012-13 Edward Kmett
-- License     :  BSD-style (see the file LICENSE)
-- Maintainer  :  Edward Kmett <ekmett@gmail.com>
-- Stability   :  experimental
-- Portability :  non-portable
--
-----------------------------------------------------------------------------
module Control.Lens.Internal.Deque
  ( Deque(..)
  , size
  , fromList
  , null
  , singleton
  ) where

import Control.Applicative
import Control.Lens.Combinators
import Control.Lens.Cons
import Control.Lens.Fold
import Control.Lens.Indexed
import Control.Lens.Prism
import Control.Monad
import Data.Foldable as Foldable
import Data.Function
import Data.Functor.Reverse
import Data.Traversable as Traversable
import Data.Monoid
import Data.Profunctor.Unsafe
import Prelude hiding (null)

-- | A Banker's deque based on Chris Okasaki's \"Purely Functional Data Structures\"
data Deque a = BD !Int [a] !Int [a]
  deriving Show

null :: Deque a -> Bool
null (BD lf _ lr _) = lf + lr == 0
{-# INLINE null #-}

singleton :: a -> Deque a
singleton a = BD 1 [a] 0 []
{-# INLINE singleton #-}

size :: Deque a -> Int
size (BD lf _ lr _) = lf + lr
{-# INLINE size #-}

fromList :: [a] -> Deque a
fromList = Prelude.foldr cons empty
{-# INLINE fromList #-}

instance Eq a => Eq (Deque a) where
  (==) = (==) `on` toList
  {-# INLINE (==) #-}

instance Ord a => Ord (Deque a) where
  compare = compare `on` toList
  {-# INLINE compare #-}

instance Functor Deque where
  fmap h (BD lf f lr r) = BD lf (fmap h f) lr (fmap h r)
  {-# INLINE fmap #-}

instance FunctorWithIndex Int Deque where
  imap h (BD lf f lr r) = BD lf (imap h f) lr (imap (\j -> h (n - j)) r)
    where !n = lf + lr

instance Applicative Deque where
  pure a = BD 1 [a] 0 []
  {-# INLINE pure #-}
  fs <*> as = fromList (toList fs <*> toList as)
  {-# INLINE (<*>) #-}

instance Alternative Deque where
  empty = BD 0 [] 0 []
  {-# INLINE empty #-}
  xs <|> ys
    | size xs < size ys = Foldable.foldr cons ys xs
    | otherwise         = Foldable.foldl snoc xs ys
  {-# INLINE (<|>) #-}

instance MonadPlus Deque where
  mzero = empty
  {-# INLINE mzero #-}
  mplus = (<|>)
  {-# INLINE mplus #-}

instance Monad Deque where
  return a = BD 1 [a] 0 []
  {-# INLINE return #-}
  ma >>= k = fromList (toList ma >>= toList . k)
  {-# INLINE (>>=) #-}

instance Foldable Deque where
  foldMap h (BD _ f _ r) = foldMap h f <> getDual (foldMap (Dual #. h) r)
  {-# INLINE foldMap #-}

instance FoldableWithIndex Int Deque where
  ifoldMap h (BD lf f lr r) = ifoldMap h f <> getDual (ifoldMap (\j -> Dual #. h (n - j)) r)
    where !n = lf + lr
  {-# INLINE ifoldMap #-}

instance Traversable Deque where
  traverse h (BD lf f lr r) = (BD lf ?? lr) <$> traverse h f <*> backwards traverse h r
  {-# INLINE traverse #-}

instance TraversableWithIndex Int Deque where
  itraverse h (BD lf f lr r) = (\f' r' -> BD lr f' lr (getReverse r')) <$> itraverse h f <*> itraverse (\j -> h (n - j)) (Reverse r)
    where !n = lf + lr
  {-# INLINE itraverse #-}

instance Monoid (Deque a) where
  mempty = BD 0 [] 0 []
  {-# INLINE mempty #-}
  mappend xs ys
    | size xs < size ys = Foldable.foldr cons ys xs
    | otherwise         = Foldable.foldl snoc xs ys
  {-# INLINE mappend #-}

check :: Int -> [a] -> Int -> [a] -> Deque a
check lf f lr r
  | lf > 3*lr + 1, i <- div (lf + lr) 2, (f',f'') <- splitAt i f = BD i f' (lf + lr - i) (r ++ reverse f'')
  | lr > 3*lf + 1, j <- div (lf + lr) 2, (r',r'') <- splitAt j r = BD (lf + lr - j) (f ++ reverse r'') j r'
  | otherwise = BD lf f lr r
{-# INLINE check #-}

instance (Choice p, Applicative f) => Cons p f (Deque a) (Deque b) a b where
  _Cons = prism (\(x,BD lf f lr r) -> check (lf + 1) (x : f) lr r) $ \ (BD lf f lr r) ->
    if lf + lr == 0
    then Left empty
    else Right $ case f of
      []     -> (head r, empty)
      (x:xs) -> (x, check (lf - 1) xs lr r)
  {-# INLINE _Cons #-}

instance (Choice p, Applicative f) => Snoc p f (Deque a) (Deque b) a b where
  _Snoc = prism (\(BD lf f lr r,x) -> check lf f (lr + 1) (x : r)) $ \ (BD lf f lr r) ->
    if lf + lr == 0
    then Left empty
    else Right $ case r of
      []     -> (empty, head f)
      (x:xs) -> (check lf f (lr - 1) xs, x)
  {-# INLINE _Snoc #-}
