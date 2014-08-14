--
-- Copyright © 2013-2014 Anchor Systems, Pty Ltd and Others
--
-- The code in this file, and the program it is a part of, is
-- made available to you by its authors as open source software:
-- you can redistribute it and/or modify it under the terms of
-- the 3-clause BSD licence.
--

{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedLists            #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE StandaloneDeriving         #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

import Control.Applicative
import Control.Lens hiding (Index, Simple, index)
import Data.Bits.Lens
import Data.ByteString (ByteString)
import qualified Data.ByteString as S
import qualified Data.ByteString.Lazy as L
import Data.Function
import Data.List
import qualified Data.Map as Map
import Data.Monoid
import Data.Tagged
import Data.Vector.Storable.ByteString
import Test.Hspec
import Test.Hspec.QuickCheck
import Test.QuickCheck
import TimeStore
import TimeStore.Algorithms
import TimeStore.Core
import TimeStore.Index


newtype MixedPayload = MixedPayload { unMixedPayload :: ByteString }
  deriving (Eq, Show)

newtype ExtendedPoint = ExtendedPoint { unExtendedPoint :: ByteString }
  deriving (Eq, Show)

newtype SimplePoint = SimplePoint { unSimplePoint :: ByteString }

instance Arbitrary MixedPayload where
    arbitrary = do
        len <- (\(Positive n) ->  n `mod` 1048576) <$> arbitrary
        MixedPayload . L.toStrict . L.fromChunks <$> go len
      where
        go :: Int -> Gen [ByteString]
        go 0 = return []
        go n = do
            p <- arbitrary
            case p of
                Left  (ExtendedPoint x) -> (x:) <$> go (pred n)
                Right (SimplePoint x)   -> (x:) <$> go (pred n)

deriving instance Arbitrary Address
deriving instance Arbitrary Time
deriving instance Arbitrary Epoch
deriving instance Arbitrary Bucket

instance Arbitrary Point where
    arbitrary =
        Point <$> arbitrary <*> arbitrary <*> arbitrary

instance Arbitrary ExtendedPoint where
    arbitrary = do
        p <- arbitrary
        let p'@(Point _ _ len) = p & address . bitAt 0 .~ True
                                   & payload .&.~ 0xff

        -- This is kind of slow
        pl <- S.pack <$> vectorOf (fromIntegral len) arbitrary
        return . ExtendedPoint $ vectorToByteString [p'] <> pl

instance Arbitrary SimplePoint where
    arbitrary = do
        p <- liftA (address . bitAt 0 .~ False) arbitrary
        return . SimplePoint $ vectorToByteString [p]

instance Arbitrary Index where
    arbitrary = do
        (Positive first) <- arbitrary
        xs <- map (\(Positive x, Positive y) -> (x, y)) <$> arbitrary
        return . Index . Map.fromList . sortBy (compare `on` fst) $ (0, first) : xs

main :: IO ()
main = hspec $
    prop "Groups ponts" propGroupsPoints

propGroupsPoints :: Index -> Index -> MixedPayload -> Bool
propGroupsPoints ix1 ix2 (MixedPayload x) =
    let (_, _, _,
         Tagged s_max, Tagged e_max) = groupMixed (Tagged ix1)  (Tagged ix2) x
    -- There is only one invariant I can think of given no knowledge of
    -- incoming data. The simple max should be less than or equal to the
    -- extended max. This is because adding an extended point will add a
    -- pointer to the simple bucket.
    in e_max <= s_max